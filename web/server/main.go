package main

import (
	"fmt"
	"net/http"
	"os"
	"path"
	"runtime"
	"strings"
)

func main() {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		fmt.Println("unable to get file location")
		return
	}

	pages := make(map[string][]byte)

	{ // html
		htmlPath := path.Join(file, "../../html")

		entries, err := os.ReadDir(htmlPath)
		if err != nil {
			fmt.Printf("unable to read html pages: %s\n", err)
			return
		}

		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			name := entry.Name()
			if !strings.HasSuffix(name, ".html") {
				continue
			}

			data, err := os.ReadFile(path.Join(htmlPath, name))
			if err != nil {
				fmt.Printf("unable to read file: %s: %s\n", entry.Name(), err)
				return
			}

			pages[name] = data
		}
	}

	assetsPath := path.Join(file, "../../static")
	http.Handle("/static/", http.StripPrefix("/static/", http.FileServer(http.Dir(assetsPath))))

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Write(pages["index.html"])
	})

	fmt.Println("Listening")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		fmt.Println(err)
	}
}
