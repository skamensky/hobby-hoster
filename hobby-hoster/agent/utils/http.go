package utils

import (
	"net/http"
)

func SendRequest(url string) {
	// Send an HTTP request to the given URL
	http.Get(url)
}