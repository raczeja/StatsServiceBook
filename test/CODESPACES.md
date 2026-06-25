# Running tests in Codespaces

# Running tests in Codespaces

This document explains how to run the functional test suite inside a GitHub
Codespace.

Requirements

- Docker or Podman with permission to run containers
- Node.js >= 18 and `npm`

Recommended: use a devcontainer that already includes Docker and Node.js. If you
don't have a devcontainer, install the dependencies inside the Codespace.

Quick steps (Ubuntu / Codespaces shell):

```bash
# Install Docker (requires sudo)
sudo apt update
sudo apt install -y docker.io
sudo usermod -aG docker $USER

# Install Node.js (example: Node 20)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# You may need to sign out/in or restart the Codespace after adding your user to the docker group
```

Run the tests

1. Make the runner executable:

```bash
chmod +x test/run-tests.sh
```

2. (Optional) choose a specific host port for the test container:

```bash
export STRAVA_TEST_PORT=8081
```

3. Start the test runner (builds the image, runs the container, executes Puppeteer tests):

```bash
./test/run-tests.sh
```

Notes

- The script will create a temporary npm project and install `puppeteer`, so `npm` must be available and able to download packages.
- The script supports either `podman` or `docker` (it prefers Podman if available).
- If you cannot install Docker/Podman in the Codespace, run the script on a local machine that has the required tools.
- For CI or developer convenience, consider adding Docker and Node to your `devcontainer.json` so Codespaces are ready-to-run.
