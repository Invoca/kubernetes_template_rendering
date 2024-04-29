## Kubernetes Template Rendering Gem

A light weight gem used to render Kubernetes manifest templates written in Jsonnet and ERB

## Getting started

Start write your documentation by adding more markdown (.md) files to this folder (/docs) or replace the content in this file.

## Table of Contents

The Table of Contents on the right is generated automatically based on the hierarchy
of headings. Only use one H1 (`#` in Markdown) per file.

## Site navigation

For new pages to appear in the left hand navigation you need edit the `mkdocs.yml`
file in root of your repo. The navigation can also link out to other sites.

Alternatively, if there is no `nav` section in `mkdocs.yml`, a navigation section
will be created for you. However, you will not be able to use alternate titles for
pages, or include links to other sites.

Note that MkDocs uses `mkdocs.yml`, not `mkdocs.yaml`, although both appear to work.
See also <https://www.mkdocs.org/user-guide/configuration/>.

## YARD documentation

To add yard generated documentation to your Technical Documention, checkou out the
[yard-to_mkdocs](https://github.com/Invoca/yard-to_mkdocs) gem and add the following steps
to the `.github/workflows/techdocs.yml` file before the `Generate Tech Docs` step:

```yaml
- uses: ruby/setup-ruby@v1
  with:
    ruby-version: '3.0'
    bundler: none
- name: Install Ruby Dependencies
  run: gem install yard yard-to_mkdocs --no-document
- name: Generate yard documentation
  run: yard doc --plugin to_mkdocs --title "Code Documentation" --output-dir docs/code
```

## Support

That's it. If you need support, reach out in [#docs-like-code](https://discord.com/channels/687207715902193673/714754240933003266) on Discord.
