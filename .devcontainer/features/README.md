# Using this

Installation of this feature collection is supposed to be done via git subrepo. For initial installation:

```
git subrepo clone https://github.com/Lupus/my-devcontainer-features .devcontainer/features
```

For updates:

```
.devcontainer/features/self_update.sh
```

## Example `.devcontainer/devcontainer.json`:

```
{
  "image": "mcr.microsoft.com/devcontainers/base:debian",
  "features": {
    "./features/common": {}
  }
}
```
