# IDE via SSH et code dans les Pods

Met en place l'organisation de l'espace de travail sur le serveur, y connecte VS Code ou PhpStorm via SSH pour modifier les fichiers sur place, et monte le répertoire du projet dans un Pod via `hostPath` afin que les changements de code soient visibles instantanément sans reconstruire d'image. Destiné au développement ; les images de production doivent embarquer leur code.

## 1. Organisation de l'espace de travail sur le serveur

```
~/workspace/
    work/<PROJECT_NAME>/       code source, dépôt Git (identité professionnelle)
    personal/<PROJECT_NAME>/   code source, dépôt Git (identité personnelle)
~/k8s-infrastructure/
    projects/<PROJECT_NAME>/   manifestes Kubernetes uniquement (pas de code source)
```

Le code et les manifestes sont séparés afin que les manifestes puissent être versionnés et appliqués indépendamment de tout dépôt d'application. Identités par répertoire : [identités Git multiples](multiple-git-identities.md).

## 2. Entrée SSH sur le portable

`~/.ssh/config` sur le portable (macOS ou Linux) ; les deux IDE peuvent la réutiliser :

```
Host <SERVER_HOSTNAME>
    HostName <SERVER_IP>
    Port <SSH_PORT>
    User <SERVER_USER>
    IdentityFile ~/.ssh/id_ed25519
```

La clé utilisée ici est celle qui sert à se connecter au serveur (son `.pub` se trouve dans `~/.ssh/authorized_keys` du serveur), pas une clé Git. Vérification : `ssh <SERVER_HOSTNAME>`.

## 3a. VS Code (Remote - SSH)

1. Installez l'extension « Remote - SSH ».
2. Palette de commandes > `Remote-SSH: Connect to Host...` > `<SERVER_HOSTNAME>`.
3. `File > Open Folder` > `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>`.

VS Code installe un petit composant serveur dans `~/.vscode-server` lors de la première connexion ; les extensions qui agissent sur les fichiers (PHP, YAML, Git) s'exécutent alors sur le serveur.

## 3b. PhpStorm

| Mode | Procédure |
|---|---|
| Remote Development (recommandé) | Écran d'accueil > Remote Development > SSH > New Connection (hôte `<SERVER_IP>`, port `<SSH_PORT>`, utilisateur `<SERVER_USER>`, fichier de clé) > choisissez la version de l'IDE et le répertoire du projet. Un backend d'IDE sans interface s'exécute sur le serveur (nécessite quelques Go de RAM) ; seule l'interface s'exécute sur le portable |
| Deployment (synchronisation SFTP) | `Settings > Build, Execution, Deployment > Deployment` > ajoutez un serveur SFTP avec les mêmes identifiants ; Mappings : répertoire local du projet vers `/home/<SERVER_USER>/workspace/work/<PROJECT_NAME>` ; activez l'envoi automatique à l'enregistrement. Le code est modifié localement et répliqué sur le serveur |

Utilisez le mode Remote Development lorsque le serveur dispose des ressources nécessaires ; utilisez Deployment sur une petite machine.

## 4. Monter le code dans un Pod (`hostPath`)

Dans le manifeste Deployment du projet :

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

- `hostPath` monte un répertoire du disque du nœud dans le conteneur, de sorte qu'enregistrer un fichier dans l'IDE modifie immédiatement l'application en cours d'exécution.
- `path` doit être absolu ; `~` n'est pas développé. `type: Directory` fait échouer le démarrage du Pod si le répertoire est absent (clonez d'abord le dépôt).
- Valable uniquement sur un cluster à nœud unique ; avec plusieurs nœuds, le Pod peut atterrir là où le répertoire n'existe pas.

```bash
kubectl apply -f deployment.yaml
```

## 5. Permissions des fichiers

Le processus dans le conteneur s'exécute sous son propre utilisateur (pour PHP-FPM : `www-data`, UID 82 sur les images Alpine, UID 33 sur les images basées sur Debian), et non sous `<SERVER_USER>`. Les répertoires dans lesquels l'application écrit (pour WordPress `wp-content`, en particulier `uploads`) doivent lui être accessibles en écriture :

```bash
cd ~/workspace/work/<PROJECT_NAME>
sudo chown -R <SERVER_USER>:<SERVER_USER> .
sudo find wp-content/ -type d -exec chmod 775 {} +
sudo find wp-content/ -type f -exec chmod 664 {} +
git config core.fileMode false
```

- `775`/`664` donnent la lecture/écriture au propriétaire et au groupe ; l'utilisateur du Pod doit être le propriétaire ou appartenir au groupe. Si l'UID ne correspond pas, faites un `chown` des répertoires en écriture vers cet UID (`sudo chown -R 82:82 wp-content/uploads`) ou, pour une installation jetable, utilisez `777`/`666`.
- `core.fileMode false` empêche Git de signaler les changements de permissions comme des modifications ; le réglage est stocké dans le `.git/config` de ce clone, répétez-le donc après chaque nouveau clonage.
- Les permissions sont perdues après certaines opérations (`git pull` créant des fichiers, extraction d'archive) : réappliquez les commandes.

## Vérification

IDE : ouvrez le terminal intégré et exécutez `hostname; pwd` ; il doit afficher le nom du serveur et un chemin `/home/<SERVER_USER>/workspace/...`.

Pod :

```bash
kubectl get pods
kubectl exec -it <pod> -- ls /var/www/html     # mêmes fichiers que dans ~/workspace/...
kubectl exec -it <pod> -- touch /var/www/html/wp-content/uploads/_t && echo writable
```

Modifiez un fichier dans l'IDE et rechargez la page : le changement est actif sans redémarrer le Pod.

| Symptôme | Solution |
|---|---|
| L'IDE ne peut pas se connecter | Le port diffère de `<SSH_PORT>` ; la clé du portable est absente de `authorized_keys` ; testez d'abord avec un simple `ssh` |
| Pod en `CreateContainerError` / bloqué en `ContainerCreating` | Répertoire `hostPath` absent ou chemin relatif ; `kubectl describe pod <pod>` |
| L'application indique « Permission denied » / « Unable to create directory » | Étape 5 |
| Git affiche tous les fichiers comme modifiés après chmod | `git config core.fileMode false` |
| Le backend Remote Development est lent ou tué | RAM insuffisante sur le serveur ; passez au mode Deployment (SFTP) |

Suite : [Conventions de structure K8s](../05-deploying-projects/k8s-structure-conventions.md)
