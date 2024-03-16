package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/go-git/go-git/v5"
	"github.com/spf13/cobra"
	"io/ioutil"
	"text/template"
)

var rootProjectDir = "/mnt/data/projects"

func getProjectPath(subdomain string) string {
	return filepath.Join(rootProjectDir, subdomain)
}


// Define a template for the Traefik dynamic configuration
const traefikConfigTemplate = `
[http.routers]
  [http.routers.{{.Subdomain}}]
    rule = "Host(`{{.subdomain}}.{{.domain}}`)"
    service = "{{.subdomain}}"
[http.services]
  [http.services.{{.subdomain}}.loadBalancer]
    [[http.services.{{.subdomain}}.loadBalancer.servers]]
      url = "http://{{.subdomain}}:80"
`

// Function to add subdomain to Traefik
func addSubdomainToTraefik(subdomain string) error {
	// Prepare the data for the template
	data := map[string]string{
		"subdomain": subdomain,
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


var rootCmd = &cobra.Command{
	Use:   "cli",
	Short: "CLI for managing services",
	Long:  `This is a CLI for managing services.`,
}

var rebuildCmd = &cobra.Command{
	Use:   "rebuild [subdomain] [domain]",
	Short: "Rebuild services",
	Long:  `This command rebuilds all services or a specific service.`,
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {

		subdomain := args[0]
		domain:=args[1]
		fullProjectDir := getProjectPath(subdomain)

		if _, err := os.Stat(fullProjectDir); os.IsNotExist(err) {
			return errors.New(fmt.Sprintf("Project directory does not exist: %v", err))
		}

		cmdDown := exec.Command("docker-compose", "-f", fullProjectDir, "down")
		err := cmdDown.Run()
		if err != nil {
			return errors.New(fmt.Sprintf("Failed to run docker-compose down: %v", err))
		}
		cmdBuild := exec.Command("docker-compose", "-f", fullProjectDir, "build")
		err = cmdBuild.Run()
		if err != nil {
			return errors.New(fmt.Sprintf("Failed to run docker-compose build: %v", err))
		}
		cmdUp := exec.Command("docker-compose", "-f", fullProjectDir, "up", "-d")
		err = cmdUp.Run()
		if err != nil {
			return errors.New(fmt.Sprintf("Failed to run docker-compose up: %v", err))
		}
		err = addSubdomainToTraefik(subdomain,domain)
		if err != nil {
			return errors.New(fmt.Sprintf("Failed to add subdomain to Traefik: %v", err))
		}
		err = reloadTraefik(subdomain)
		if err != nil {
			return errors.New(fmt.Sprintf("Failed to reload Traefik: %v", err))
		}

		return nil
	},
}

var cloneCmd = &cobra.Command{
	Use:   "clone [repo-url] [subdomain]",
	Short: "Clone a GitHub repository",
	Long:  `This command clones a GitHub repository to a specific directory and commits.`,
	Args:  cobra.ExactArgs(2),
	RunE: func(cmd *cobra.Command, args []string) error {
		repo := args[0]
		subdomain := args[1]
		fullProjectDir := getProjectPath(subdomain)
		_, err := git.PlainClone(fullProjectDir, false, &git.CloneOptions{
			URL:      repo,
			Progress: os.Stdout,
			Depth:    1,
		})
		if err != nil {
			return errors.New(fmt.Sprintf("Failed to clone repository: %v", err))
		}

		return nil
	},
}

func main() {
	rootCmd.AddCommand(rebuildCmd)
	rootCmd.AddCommand(cloneCmd)
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
