# SQL Server Availability Group in Docker (Clusterless)

This repository contains a set of PowerShell scripts to automatically create a **clusterless SQL Server Availability Group** with three nodes hosted in Docker containers.

The scripts are designed to quickly build and tear down SQL Server Docker containers on a personal desktop for testing various SQL Server features and database deployments.

## Features

- **Quick Setup**: Quickly create a multi-node SQL Server Availability Group in Docker.
- **Self-Cleaning**: Easily tear down containers and data folders when not in use.
- **Sample Database**: The `AdventureWorks` sample database is automatically added to the Availability Group.

## Scripts

- ### `cleanup.ps1`
  Cleans up the environment by removing all Docker containers and associated local data folders.

- ### `go.ps1`
  - Installs required PowerShell modules.
  - Builds a custom SQL Server Docker image.
  - Creates SQL Server containers using Docker Compose.
  - Configures a clusterless Always On Availability Group.
  - Downloads and places the `AdventureWorks` sample database into the Availability Group.

## Usage

### Prerequisites

- Docker Desktop installed and running.
- PowerShell 7+ installed.
- Optional: [AdventureWorks](https://github.com/Microsoft/sql-server-samples/releases/tag/adventureworks) database files (downloaded automatically).

### Quick Start

1. Clone this repository:
   ```pwsh
   git clone <repository-url>
2. Run the setup script:
    ```pwsh
    ./go.ps1
3. To cleanup the environment
    ```pwsh
    ./cleanup.ps1

### Notes
- The environment is built for testing and development purposes on a local desktop.
- Modify the scripts as needed for your specific testing scenarios.