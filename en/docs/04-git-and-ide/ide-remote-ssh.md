# IDE over SSH and Code in Pods

Sets up the workspace layout on the server, connects VS Code or PhpStorm to it over SSH so files are edited in place, and mounts the project directory into a Pod through `hostPath` so code changes are visible instantly without rebuilding an image. Intended for development; production images should carry their code.

## 1. Workspace layout on the server

```
~/workspace/
    work/<PROJECT_NAME>/       source code, Git repository (work identity)
    personal/<PROJECT_NAME>/   source code, Git repository (personal identity)
~/k8s-infrastructure/
    projects/<PROJECT_NAME>/   Kubernetes manifests only (no source code)
```

Code and manifests are kept apart so that manifests can be versioned and applied independently of any application repository. Identities per directory: [multiple Git identities](multiple-git-identities.md).

## 2. SSH entry on the laptop

`~/.ssh/config` on the laptop (macOS or Linux); both IDEs can reuse it:

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    Port <SSH_PORT>
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
```

The key here is the one used to log in to the server (its `.pub` is in the server's `~/.ssh/authorized_keys`), not a Git key. Check: `ssh <SERVER_HOSTNAME>`.

## 3a. VS Code (Remote - SSH)

1. Install the extension "Remote - SSH".
2. Command Palette > `Remote-SSH: Connect to Host...` > `<SERVER_HOSTNAME>`.
3. `File > Open Folder` > `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>`.

VS Code installs a small server component under `~/.vscode-server` on the first connection; extensions that act on files (PHP, YAML, Git) then run on the server.

## 3b. PhpStorm

| Mode | How |
|---|---|
| Remote Development (recommended) | Welcome screen > Remote Development > SSH > New Connection (host `<SERVER_IP>`, port `<SSH_PORT>`, user `<SERVER_USER>`, key file) > choose the IDE version and the project directory. A headless IDE backend runs on the server (needs a few GB of RAM); only the UI runs on the laptop |
| Deployment (SFTP sync) | `Settings > Build, Execution, Deployment > Deployment` > add an SFTP server with the same credentials; Mappings: local project directory to `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>`; enable automatic upload on save. Code is edited locally and mirrored to the server |

Use the Remote Development mode when the server has the resources; use Deployment on a small box.

## 4. Mount the code into a Pod (`hostPath`)

In the Deployment manifest of the project:

```yaml
      containers:
      - name: app
        image: <APP_IMAGE>
        volumeMounts:
        - name: app-code
          mountPath: /var/www/html
      volumes:
      - name: app-code
        hostPath:
          path: /home/<SERVER_USER>/workspace/work/<PROJECT_NAME>
          type: Directory
```

- `hostPath` mounts a directory of the node's disk into the container, so saving a file in the IDE changes the running app at once.
- `path` must be absolute; `~` is not expanded. `type: Directory` makes the Pod fail to start if the directory is missing (clone the repository first).
- Valid only on a single-node cluster; with several nodes the Pod can land where the directory does not exist.

```bash
kubectl apply -f deployment.yaml
```

## 5. File permissions

The process in the container runs as its own user (for PHP-FPM: `www-data`, UID 82 on Alpine images, UID 33 on Debian-based images), not as `<SERVER_USER>`. Directories the app writes to (for WordPress `wp-content`, especially `uploads`) must be writable by it:

```bash
cd ~/workspace/work/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> .
sudo find wp-content/ -type d -exec chmod 775 {} +
sudo find wp-content/ -type f -exec chmod 664 {} +
git config core.fileMode false
```

- `775`/`664` give owner and group read/write; the Pod's user must be the owner or in the group. If the UID does not match, either `chown` the writable directories to that UID (`sudo chown -R 82:82 wp-content/uploads`) or, for a throwaway setup, use `777`/`666`.
- `core.fileMode false` stops Git from reporting permission changes as modifications; it is stored in that clone's `.git/config`, so repeat it after every fresh clone.
- Permissions are lost after some operations (`git pull` creating files, archive extraction): re-apply the commands.

## Verify

IDE: open the built-in terminal and run `hostname; pwd`; it must print the server's name and a `/home/<SERVER_USER>/workspace/...` path.

Pod:

```bash
kubectl get pods
kubectl exec -it <pod> -- ls /var/www/html     # same files as in ~/workspace/...
kubectl exec -it <pod> -- touch /var/www/html/wp-content/uploads/_t && echo writable
```

Edit a file in the IDE and reload the page: the change is live without restarting the Pod.

| Symptom | Fix |
|---|---|
| IDE cannot connect | Port differs from `<SSH_PORT>`; the laptop's key is missing in `authorized_keys`; test with plain `ssh` first |
| Pod `CreateContainerError` / stuck `ContainerCreating` | `hostPath` directory missing or relative path; `kubectl describe pod <pod>` |
| App says "Permission denied" / "Unable to create directory" | Step 5 |
| Git shows every file modified after chmod | `git config core.fileMode false` |
| Remote Development backend is slow or killed | Not enough RAM on the server; switch to Deployment (SFTP) mode |

Next: [K8s structure conventions](../05-deploying-projects/k8s-structure-conventions.md)
