# dspacer

An R client for downloading metadata and text from DSpace repositories. Retrieve
item metadata, inventory attachments, and turn selected Markdown files into
plaintext for analysis.

**Early development:** read-only, modern DSpace REST API only. Compatibility
testing against real repositories is still pending.

## Install from GitHub

Install the development version from GitHub:

```r
install.packages("remotes") # Only needed once
library(remotes)
install_github("Hegghammer/dspacer")
```

## Quick start

Replace the example URL below with your repository's actual REST API URL.
For restricted content, set `DSPACE_USER` and `DSPACE_PASSWORD` in your environment
to your **DSpace** login credentials.

```r
library(dspacer)

con <- ds_connect("https://repository.example.org/server/api")

# Omit this step for anonymous access to public content.
ds_login(
  con,
  user = Sys.getenv("DSPACE_USER"),
  password = Sys.getenv("DSPACE_PASSWORD")
)

items <- ds_get_items(con)
metadata <- ds_get_metadata(items)
ds_disconnect(con)
```

## Documentation

- [Authentication](vignettes/authentication.Rmd)
- [Retrieving metadata](vignettes/metadata.Rmd)
- [Working with text and files](vignettes/texts.Rmd)

Function help, such as `?ds_get_items` and `?ds_get_texts`, describes arguments,
returned columns and technical behaviour.
