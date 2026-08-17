# Docker Root + Bind Mount Security Demo

A classroom practical demonstrating why running a Docker container as `root` and giving it access to a host directory through a bind mount can create a security risk.

## Learning Objectives

By the end of this demo, students should understand:

- How a Dockerfile creates an image.
- Why a container may run as `root` by default.
- How to check the container user and UID.
- What a bind mount is.
- How a container can read and modify host-mounted data.
- Why `/opt`, `/home`, `/tmp`, etc. are not inherently safe just because they are outside `/root`.
- How the `USER` instruction can reduce risk.
- Why least privilege matters.

> **Safety:** Perform this demo only on a disposable lab VM or test machine. Do not mount sensitive production directories.

---

## 1. Prerequisites

Check Docker:

```bash
docker --version
docker info
```

---

## 2. Create the Demo Directory

```bash
mkdir -p ~/docker-root-volume-demo
cd ~/docker-root-volume-demo
```

Verify:

```bash
pwd
ls -la
```

---

# Part A — Create a Root-Based Image

## 3. Create the Dockerfile

Create `Dockerfile`:

```dockerfile
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y curl

RUN useradd -m appuser

CMD ["bash"]
```

### Important Observation

There is no:

```dockerfile
USER appuser
```

Therefore the container starts with the default user from the base image.

For Ubuntu, this is normally:

```text
root
```

---

## 4. Build the Image

```bash
docker build -t root-demo .
```

Check:

```bash
docker images
```

---

## 5. Inspect the Image User

```bash
docker image inspect root-demo --format '{{.Config.User}}'
```

If nothing is returned, no explicit `USER` is configured in the image.

Run the image:

```bash
docker run --rm -it root-demo
```

Inside the container:

```bash
whoami
id
```

Expected:

```text
root
uid=0(root) gid=0(root)
```

Exit:

```bash
exit
```

---

# Part B — Create Host Data

## 6. Create a Host Directory

Use `/opt` to prove that the host path does **not** have to be under `/root`.

On the Docker host:

```bash
sudo mkdir -p /opt/docker-root-demo
```

Create a file:

```bash
echo "IMPORTANT HOST DATA" | sudo tee /opt/docker-root-demo/secret.txt
```

Read it:

```bash
cat /opt/docker-root-demo/secret.txt
```

Expected:

```text
IMPORTANT HOST DATA
```

Check permissions:

```bash
ls -ln /opt/docker-root-demo/secret.txt
```

---

# Part C — Mount Host Directory into Root Container

## 7. Start the Root Container with a Bind Mount

```bash
docker run --rm -it \
  -v /opt/docker-root-demo:/data \
  root-demo
```

Inside the container:

```bash
whoami
```

Expected:

```text
root
```

List the mounted directory:

```bash
ls -l /data
```

You should see:

```text
secret.txt
```

Read the host file:

```bash
cat /data/secret.txt
```

Expected:

```text
IMPORTANT HOST DATA
```

---

# Part D — Demonstrate the Security Problem

## 8. Modify the Host File from the Container

Inside the container:

```bash
echo "MODIFIED BY ROOT CONTAINER" > /data/secret.txt
```

Verify from inside:

```bash
cat /data/secret.txt
```

Exit:

```bash
exit
```

Now check the file from the **host**:

```bash
cat /opt/docker-root-demo/secret.txt
```

Expected:

```text
MODIFIED BY ROOT CONTAINER
```

### Key Observation

The container modified a file that physically exists on the host.

The reason is:

```text
Host directory
      |
      | bind mount
      v
Container /data
      |
      v
Container process can access host-mounted data
```

---

# 9. Visual Explanation

```text
                    DOCKER HOST
┌─────────────────────────────────────────────┐
│                                             │
│  /opt/docker-root-demo                     │
│          │                                  │
│          │ bind mount                       │
│          ▼                                  │
│  ┌───────────────────────────────┐          │
│  │           CONTAINER           │          │
│  │                               │          │
│  │       Process = root          │          │
│  │              │                │          │
│  │              ▼                │          │
│  │            /data              │          │
│  │                               │          │
│  └───────────────────────────────┘          │
│                                             │
└─────────────────────────────────────────────┘
```

The important point:

> `/data` is a view of the host directory `/opt/docker-root-demo`. It is not independent container storage.

---

# Part E — Prove the Mount Using docker inspect

## 10. Start a Background Container

```bash
docker run -d \
  --name mount-demo \
  -v /opt/docker-root-demo:/data \
  root-demo \
  sleep 1000
```

Check:

```bash
docker ps
```

Inspect mounts:

```bash
docker inspect mount-demo --format '{{json .Mounts}}'
```

You should see information similar to:

```text
Source: /opt/docker-root-demo
Destination: /data
```

Enter the container:

```bash
docker exec -it mount-demo bash
```

Inside:

```bash
whoami
ls -l /data
```

Exit:

```bash
exit
```

Remove the container:

```bash
docker rm -f mount-demo
```

The host file remains:

```bash
cat /opt/docker-root-demo/secret.txt
```

---

# Part F — Create a Non-Root Image

## 11. Modify the Dockerfile

Replace the Dockerfile with:

```dockerfile
FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y curl

RUN useradd -m appuser

USER appuser

CMD ["bash"]
```

The important line is:

```dockerfile
USER appuser
```

---

## 12. Build the Non-Root Image

```bash
docker build -t nonroot-demo .
```

Check:

```bash
docker images
```

---

## 13. Run as Non-Root

```bash
docker run --rm -it \
  -v /opt/docker-root-demo:/data \
  nonroot-demo
```

Inside:

```bash
whoami
```

Expected:

```text
appuser
```

Check UID:

```bash
id
```

Expected similar to:

```text
uid=1000(appuser) gid=1000(appuser)
```

---

# Part G — Try to Modify the Host File

Inside the non-root container:

```bash
echo "TRY TO MODIFY" > /data/secret.txt
```

Depending on the ownership and permissions of the host directory/file, this should fail with:

```text
Permission denied
```

### Why?

The container process is no longer:

```text
UID 0
```

It is running as a normal user.

This is an example of the **least-privilege principle**.

---

# Part H — Important Concept: `/root` vs `/opt`

The security issue is **not** specifically related to `/root`.

All of these can be host paths:

```text
/root/data
/home/user/data
/opt/app/data
/var/lib/app
/tmp/demo
```

The important relationship is:

```text
Host path
   ↓
Bind mount
   ↓
Container path
   ↓
Container user
   ↓
Host filesystem permissions
```

Therefore:

> `/opt` is not automatically safe, and `/root` is not the only sensitive location.

---

# Useful Docker Commands

## Build

```bash
docker build -t root-demo .
```

## Build with a different Dockerfile

```bash
docker build -t nonroot-demo -f Dockerfile .
```

## List images

```bash
docker images
```

## Run interactive container

```bash
docker run --rm -it root-demo
```

## Run detached

```bash
docker run -d --name demo root-demo sleep 1000
```

## List running containers

```bash
docker ps
```

## List all containers

```bash
docker ps -a
```

## Execute a shell inside a running container

```bash
docker exec -it demo bash
```

## Inspect a container

```bash
docker inspect demo
```

## Inspect mounts

```bash
docker inspect demo --format '{{json .Mounts}}'
```

## Inspect image user

```bash
docker image inspect root-demo --format '{{.Config.User}}'
```

## Stop a container

```bash
docker stop demo
```

## Remove a container

```bash
docker rm demo
```

## Force remove a container

```bash
docker rm -f demo
```

## Remove an image

```bash
docker rmi root-demo
```

---

# Cleanup

Remove containers:

```bash
docker rm -f mount-demo 2>/dev/null || true
```

Remove images:

```bash
docker rmi root-demo nonroot-demo
```

Remove the host test directory:

```bash
sudo rm -rf /opt/docker-root-demo
```

Remove the working directory:

```bash
rm -rf ~/docker-root-volume-demo
```

---

# Interview Questions

## Q1. If a container runs as root, is it automatically root on the host?

**No.**

Container isolation normally prevents a root process inside a container from automatically becoming unrestricted root on the host.

---

## Q2. Then why is a root container risky?

Because a root process has more privileges inside the container, and the risk increases when the container is given access to host resources.

Examples include:

```text
--privileged
Bind mounts
Host namespaces
Excessive Linux capabilities
Kernel/runtime vulnerabilities
```

---

## Q3. Does mounting `/opt` make it safe?

**No.**

The directory name is not the security boundary.

Permissions and isolation are what matter.

---

## Q4. What is the recommended Dockerfile practice?

Create a dedicated application user and use:

```dockerfile
USER appuser
```

---

## Q5. Does deleting a container delete bind-mounted data?

**No.**

```text
Container deleted
       |
       X
       |
Host bind-mounted data remains
```

The data belongs to the host filesystem.

---

# Final Takeaway

```text
Dockerfile
    |
    v
Image
    |
    v
Container
    |
    v
Default user = root
    |
    +----------------------+
    |                      |
    v                      v
Container filesystem    Bind mount
                           |
                           v
                    Host filesystem
                           |
                           v
                  Possible data access
                           |
                           v
                     SECURITY RISK
```

## Best Practices

```text
1. Run applications as non-root.
2. Use USER in the Dockerfile.
3. Avoid unnecessary bind mounts.
4. Mount only the directories the application needs.
5. Avoid --privileged unless absolutely required.
6. Use least privilege.
7. Understand host filesystem permissions.
8. Treat host-mounted data as host data.
```

## One-Line Interview Answer

> **A root container is not automatically host-root, but combining root privileges with access to host resources such as bind-mounted directories can allow the container to read or modify host data; therefore containers should follow least privilege and run as non-root whenever possible.**
