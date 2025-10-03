# nix
My adventures with Nix

## DMD - Demystifying Nix

This repository contains a Quarto book about Nix, covering topics from basic concepts to advanced usage.

### Building the Book

To build the book, you need to have [Quarto](https://quarto.org) installed.

```bash
# Preview the book (opens in browser with live reload)
quarto preview

# Render the book to HTML
quarto render

# Render to PDF (requires LaTeX)
quarto render --to pdf
```

The rendered book will be in the `_book/` directory.

### Contents

- **Introduction**: What is Nix and why use it
- **Basics**: Core concepts and basic commands
- **Package Management**: Installing, managing, and creating packages
- **Development Shells**: Reproducible development environments
- **References**: Links to resources and bibliography
