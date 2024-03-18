package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"text/template"

	"github.com/go-git/go-git/v5"
	"github.com/spf13/cobra"

	"strconv"

	"gopkg.in/yaml.v2"
)

var ROOT_PROJECT_DIR = "/mnt/data/projects"
var LAST_PORT_FILE = "/mnt/data/last-host-port.txt"

var LAST_PORT_MUT = &sync.Mutex{}

func getProjectPath(subdomain string) string {
	return filepath.Join(ROOT_PROJECT_DIR, subdomain)
}

type CmdWrap struct {
	cmd    *exec.Cmd
	stdout bytes.Buffer
	stderr bytes.Buffer
	err    error
}

func NewCmdWrap(dir string, name string, arg ...string) *CmdWrap {
	c := &CmdWrap{}
	c.cmd = exec.Command(name, arg...)
	c.cmd.Dir = dir
	return c
}

func (c *CmdWrap) Run() {
	c.cmd.Stdout = &c.stdout
	c.cmd.Stderr = &c.stderr
	c.err = c.cmd.Run()

}

func (c *CmdWrap) Error() error {
	if c.err != nil {
		return fmt.Errorf("Failed to run %s: %v, stdout: %s, stderr: %s", c.cmd.String(), c.err, c.stdout.String(), c.stderr.String())
	}
	return nil
}

func (c *CmdWrap) ErrorAsJson() string {
	errorMap := map[string]string{
		"stdout":  c.stdout.String(),
		"stderr":  c.stderr.String(),
		"error":   fmt.Sprint(c.err),
		"command": c.cmd.String(),
	}
	jsonError, _ := json.Marshal(errorMap)
	return string(jsonError)
}

// Define a template for the Traefik dynamic configuration
const traefikConfigTemplate = `
[http.routers]
  [http.routers.{{.Subdomain}}]
    rule = "Host({{.subdomain}}.{{.domain}})"
    service = "{{.subdomain}}"
[http.services]
  [http.services.{{.subdomain}}.loadBalancer]
    [[http.services.{{.subdomain}}.loadBalancer.servers]]
      url = "http://{{.subdomain}}:80"
`

func removeSubdomainFromTreafik(subdomain string) error {
	// Remove the subdomain configuration file from Traefik's dynamic configuration directory
	filePath := filepath.Join("/mnt/data/traefik", subdomain+".toml")
	if err := os.Remove(filePath); err != nil {
		return fmt.Errorf("failed to remove subdomain configuration for %s: %w", subdomain, err)
	}

	// Reload Traefik to apply changes
	if err := reloadTraefik(); err != nil {
		return fmt.Errorf("failed to reload Traefik after removing subdomain %s: %w", subdomain, err)
	}

	return nil
}

// Function to add subdomain to Traefik
func addSubdomainToTraefik(subdomain string, domain string) error {
	// Prepare the data for the template
	data := map[string]string{
		"subdomain": subdomain,
		"domain":    domain,
	}

	// Create a new template and parse the configuration into it
	t := template.New("traefikConfig")
	t, err := t.Parse(traefikConfigTemplate)
	if err != nil {
		return err
	}

	// Execute the template and write the output to a file
	filePath := filepath.Join("/mnt/data/traefik", subdomain+".toml")
	file, err := os.Create(filePath)
	if err != nil {
		return err
	}
	defer file.Close()

	err = t.Execute(file, data)
	if err != nil {
		return err
	}

	// Reload Traefik
	err = reloadTraefik()
	if err != nil {
		return err
	}

	return nil
}

// Function to reload Traefik
func reloadTraefik() error {
	// Traefik can be reloaded by sending a SIGHUP signal
	// Get the Traefik process ID
	pid, err := exec.Command("pidof", "traefik").Output()
	if err != nil {
		return err
	}

	// Send the SIGHUP signal
	err = exec.Command("kill", "-HUP", string(pid)).Run()
	if err != nil {
		return err
	}

	return nil
}

type Service struct {
	Subdomain  string `json:"subdomain"`
	LastCommit string `json:"last_commit"`
}

func listServices() ([]Service, error) {
	services := []Service{}
	projectDir := ROOT_PROJECT_DIR

	files, err := os.ReadDir(projectDir)
	if err != nil {
		return nil, err
	}

	for _, f := range files {
		if f.IsDir() {

			cmd := exec.Command("git", "-C", projectDir+"/"+f.Name(), "rev-parse", "HEAD")
			lastCommit, err := cmd.Output()
			if err != nil {
				return nil, err
			}
			lastCommitString := strings.TrimSpace(string(lastCommit))
			services = append(services, Service{Subdomain: f.Name(), LastCommit: lastCommitString})
		}
	}

	return services, nil
}

func initializePortFile(restartCount bool) error {
	initialPort := "1024"
	if _, err := os.Stat(LAST_PORT_FILE); os.IsNotExist(err) {
		file, err := os.Create(LAST_PORT_FILE)
		if err != nil {
			return err
		}
		defer file.Close()

		// Set initial value to a safe port
		_, err = file.WriteString(initialPort)
		if err != nil {
			return err
		}
	}

	if restartCount {
		// Reset the port file to the initial port
		file, err := os.OpenFile(LAST_PORT_FILE, os.O_WRONLY|os.O_TRUNC, 0644)
		if err != nil {
			return err
		}
		defer file.Close()

		_, err = file.WriteString(initialPort)
		if err != nil {
			return err
		}
	}
	return nil
}

func allocatePorts(fullProjectDir string) error {
	/*
		since we have many docker compose projects running at the same time, we need to verify that none are using the same host ports.
		To do this, we modify the host port in place to a known unused port.

		All possible syntaxes:

		- "3000"
		- "3000-3005" - NOT SUPPORTED
		- "8000:8000"
		- "9090-9091:8080-8081" - NOT SUPPORTED
		- "49100:22"
		- "127.0.0.1:8001:8001"
		- "127.0.0.1:5000-5010:5000-5010" - NOT SUPPORTED
		- "127.0.0.1::5000"  - NOT SUPPORTED
		- "6060:6060/udp" - NOT SUPPORTED
		- "12400-12500:1240" - NOT SUPPORTED


		Anything not supported will fail the deploy
	*/

	LAST_PORT_MUT.Lock()
	defer LAST_PORT_MUT.Unlock()

	if _, err := os.Stat(LAST_PORT_FILE); os.IsNotExist(err) {
		file, err := os.Create(LAST_PORT_FILE)
		if err != nil {
			return err
		}
		defer file.Close()

		// Set initial value to a safe port
		initialPort := "1024"
		_, err = file.WriteString(initialPort)
		if err != nil {
			return err
		}
	}

	// Read the last allocated port
	data, err := os.ReadFile(LAST_PORT_FILE)
	if err != nil {
		return err
	}
	lastPort, err := strconv.Atoi(string(data))
	if err != nil {
		return err
	}

	// Parse the docker-compose.yml file
	data, err = os.ReadFile(fullProjectDir + "/docker-compose.yml")
	if err != nil {
		return err
	}
	var dockerCompose map[interface{}]interface{}
	err = yaml.Unmarshal(data, &dockerCompose)
	if err != nil {
		return err
	}

	// Iterate over the services and allocate ports
	services := dockerCompose["services"].(map[interface{}]interface{})
	for serviceName, service := range services {
		serviceMap := service.(map[interface{}]interface{})
		ports := serviceMap["ports"].([]interface{})
		for i, port := range ports {
			switch p := port.(type) {
			case int:
				// same as single port logic
				lastPort++
				ports[i] = fmt.Sprintf("%d:%d", lastPort, p)
			case string: // short syntax
				// support for   - "3000" format (maps 3000 to 3000):
				singlePortRe := regexp.MustCompile(`^(\d+)$`)
				singlePortMatches := singlePortRe.FindStringSubmatch(p)
				if singlePortMatches != nil {
					lastPort++
					ports[i] = fmt.Sprintf("%d:%v", lastPort, port)
					continue
				}

				// Match IP address and port

				re := regexp.MustCompile(`^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:)?(\d+):(\d+)$`)

				matches := re.FindStringSubmatch(p)
				if matches == nil {
					return errors.New("Invalid short port mapping in docker-compose.yml")
				}
				lastPort++
				ports[i] = fmt.Sprintf("%s%d:%s", matches[1], lastPort, matches[3])
			case map[interface{}]interface{}: // long syntax
				if target, ok := p["target"].(int); ok {
					lastPort++
					p["published"] = lastPort
					portString := fmt.Sprintf("%d:%d", target, p["published"].(int))
					re := regexp.MustCompile(`^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:)?(\d+):(\d+)$`)
					matches := re.FindStringSubmatch(portString)
					if matches == nil {
						return errors.New("Invalid long port mapping in docker-compose.yml")
					}
					ports[i] = map[string]int{"target": target, "published": lastPort}
				}
			default:
				return fmt.Errorf("Unsupported port type: %T", p)
			}

		}
		serviceMap["ports"] = ports
		services[serviceName.(string)] = serviceMap
	}
	dockerCompose["services"] = services

	// Write the updated docker-compose.yml file
	data, err = yaml.Marshal(dockerCompose)
	if err != nil {
		return err
	}
	err = os.WriteFile(fullProjectDir+"/docker-compose.yml", data, 0644)
	if err != nil {
		return err
	}

	// Update the last allocated port
	err = os.WriteFile(LAST_PORT_FILE, []byte(strconv.Itoa(lastPort)), 0644)
	if err != nil {
		return err
	}

	return nil
}

var rootCmd = &cobra.Command{
	Use:   "cli",
	Short: "CLI for managing services",
	Long:  `This is a CLI for managing services.`,
}

var listServicesCmd = &cobra.Command{
	Use:   "list-services",
	Short: "List all services",
	Long:  `This command lists all the services.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		services, err := listServices()
		jsonOutput, _ := cmd.Flags().GetBool("json")

		if err != nil {
			if jsonOutput {
				errorJson, _ := json.Marshal(map[string]interface{}{"error": err.Error()})
				fmt.Println(string(errorJson))
				return nil
			} else {
				return err
			}
		}

		servicesJSON, _ := json.Marshal(services)
		if jsonOutput {
			fmt.Println(string(servicesJSON))
		} else {
			for _, service := range services {
				fmt.Println(service.Subdomain)
			}
		}
		return nil
	},
}

func rebuildService(domain string, subdomain string) error {
	fullProjectDir := getProjectPath(subdomain)

	if _, err := os.Stat(fullProjectDir); os.IsNotExist(err) {
		return errors.New(fmt.Sprintf("Project directory does not exist: %v", err))
	}

	cmdDown := NewCmdWrap(fullProjectDir, "docker", "compose", "down")
	cmdDown.Run()
	if cmdDown.Error() != nil {
		// check if compose project is still up, could have just been down or non existent to get to this condition
		cmdPs := NewCmdWrap(fullProjectDir, "docker", "compose", "ps")
		cmdPs.Run()
		if cmdPs.Error() != nil {
			return fmt.Errorf("Failed to run docker compose ps: %v, original error: %v", cmdPs.Error(), cmdDown.Error())
		}
	}
	cmdBuild := NewCmdWrap(fullProjectDir, "docker", "compose", "build")
	cmdBuild.Run()
	if cmdBuild.Error() != nil {
		return fmt.Errorf("Failed to run docker compose build: %v", cmdBuild.Error())
	}
	err := allocatePorts(fullProjectDir)
	if err != nil {
		return err
	}
	cmdUp := NewCmdWrap(fullProjectDir, "docker", "compose", "up", "-d")
	cmdUp.Run()
	if cmdUp.Error() != nil {
		return errors.New(fmt.Sprintf("Failed to run docker compose up: %v", cmdUp.Error()))
	}
	err := addSubdomainToTraefik(subdomain, domain)
	if err != nil {
		return errors.New(fmt.Sprintf("Failed to add subdomain to Traefik: %v", err))
	}
	err = reloadTraefik()
	if err != nil {
		return errors.New(fmt.Sprintf("Failed to reload Traefik: %v", err))
	}

	return nil
}

func removeService(subdomain string) error {
	fullProjectDir := getProjectPath(subdomain)
	if _, err := os.Stat(fullProjectDir); os.IsNotExist(err) {
		return errors.New(fmt.Sprintf("Project directory does not exist: %v", err))
	}
	cmdDown := exec.Command("docker", "compose", "down")
	cmdDown.Dir = fullProjectDir
	err := cmdDown.Run()
	if err != nil {
		return errors.New(fmt.Sprintf("Failed to run docker compose down: %v", err))
	}

	err = removeSubdomainFromTreafik(subdomain)
	if err != nil {
		return errors.New(fmt.Sprintf("Failed to remove subdomain from Traefik: %v", err))
	}

	err = reloadTraefik()

	return nil
}

var rebuildCmd = &cobra.Command{
	Use:   "rebuild [domain] [subdomain1] [subdomain2] ...",
	Short: "Rebuild services",
	Long:  `This command rebuilds all services or a specific service. Pass '--all' to rebuild all services. Alternatively, you can pass multiple subdomains to rebuild specific services.`,
	Args:  cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		domain := args[0]
		subdomains := args[1:]
		var rebuildErrors []string
		jsonOutput, _ := cmd.Flags().GetBool("json")

		all, err := cmd.Flags().GetBool("all")
		if err != nil {
			return errors.New(fmt.Sprintf("Failed to get 'all' flag: %v", err))
		}

		if all {
			// take this opportunity to reset the port file
			err := initializePortFile(true)
			if err != nil {
				if jsonOutput {
					errorJson, _ := json.Marshal(map[string]interface{}{"error": err.Error()})
					fmt.Println(string(errorJson))
					return nil
				} else {
					return err
				}
			}

			services, err := listServices()
			if err != nil {
				if jsonOutput {
					errorJson, _ := json.Marshal(map[string]interface{}{"error": err.Error()})
					fmt.Println(string(errorJson))
					return nil
				} else {
					return err
				}
			}
			for _, service := range services {
				subdomains = append(subdomains, service.Subdomain)
			}
		}

		for _, subdomain := range subdomains {
			err := rebuildService(domain, subdomain)
			if err != nil {
				rebuildErrors = append(rebuildErrors, fmt.Sprintf("Failed to rebuild service %v repository: %v", subdomain, err))
				continue
			}
		}

		if len(rebuildErrors) > 0 {
			if jsonOutput {
				jsonErrors, _ := json.Marshal(map[string]interface{}{"error": strings.Join(rebuildErrors, "; ")})
				fmt.Println(string(jsonErrors))
				return nil
			} else {
				return errors.New(fmt.Sprintf("Encountered errors during rebuilding: %v", strings.Join(rebuildErrors, "; ")))
			}
		}
		if jsonOutput {
			fmt.Println(`{"success": true}`)
		}
		return nil
	},
}
var cloneCmd = &cobra.Command{
	Use:   "clone [repo-url] [subdomain]...",
	Short: "Clone GitHub repositories",
	Long:  `This command clones multiple GitHub repositories to specific directories and commits.`,
	Args:  cobra.MinimumNArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		var errs []string
		for i := 0; i < len(args); i += 2 {
			repo := args[i]
			subdomain := args[i+1]
			fullProjectDir := getProjectPath(subdomain)

			if _, err := os.Stat(fullProjectDir); !os.IsNotExist(err) {
				err := os.RemoveAll(fullProjectDir)
				if err != nil {
					errs = append(errs, fmt.Sprintf("Failed to remove existing directory %s: %v", fullProjectDir, err))
					continue
				}
			}

			_, err := git.PlainClone(fullProjectDir, false, &git.CloneOptions{
				URL:   repo,
				Depth: 1,
			})
			if err != nil {
				errs = append(errs, fmt.Sprintf("Failed to clone repository %s: %v", repo, err))
				continue
			}

			if _, err := os.Stat(fullProjectDir + "/docker-compose.yml"); os.IsNotExist(err) {
				errs = append(errs, fmt.Sprintf("docker-compose.yml does not exist in the root of the cloned repository %s", repo))
			}
		}

		jsonOutput, _ := cmd.Flags().GetBool("json")
		if len(errs) > 0 {
			if jsonOutput {
				jsonErrors, _ := json.Marshal(map[string]interface{}{"error": strings.Join(errs, "; ")})
				fmt.Println(string(jsonErrors))
				return nil
			} else {
				return errors.New(fmt.Sprintf("Encountered errors during cloning: %v", strings.Join(errs, "; ")))
			}
		} else {
			fmt.Println(`{"success": true}`)
		}
		return nil
	},
}

var removeServicesCmd = &cobra.Command{
	Use:   "remove [subdomain]...",
	Short: "Remove services",
	Long:  `This command removes one or more services by their subdomains.`,
	Args:  cobra.MinimumNArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		var errs []string
		for _, subdomain := range args {
			err := removeService(subdomain)
			if err != nil {
				errs = append(errs, fmt.Sprintf("Failed to remove service %s: %v", subdomain, err))
				continue
			}
		}

		jsonOutput, _ := cmd.Flags().GetBool("json")
		if len(errs) > 0 {
			if jsonOutput {
				jsonErrors, _ := json.Marshal(map[string]interface{}{"error": strings.Join(errs, "; ")})
				fmt.Println(string(jsonErrors))
				return nil
			} else {
				return errors.New(fmt.Sprintf("Encountered errors during service removal: %v", strings.Join(errs, "; ")))
			}
		}

		if jsonOutput {
			fmt.Println(`{"success": true}`)
		}
		return nil
	},
}

func main() {
	rootCmd.PersistentFlags().Bool("json", false, "Output in JSON format")
	rebuildCmd.Flags().Bool("all", false, "Rebuild all services")

	rootCmd.AddCommand(cloneCmd)
	rootCmd.AddCommand(listServicesCmd)
	rootCmd.AddCommand(removeServicesCmd)
	rootCmd.AddCommand(rebuildCmd)
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
