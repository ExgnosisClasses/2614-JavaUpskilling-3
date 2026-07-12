# Lab 3.0 Part 1 - Oracle Environment Setup

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**
**Module 6 | Estimated time: 30-45 minutes | Tools: SQL\*Plus or Docker, IntelliJ IDEA Ultimate**

---

## Overview

Before you can tune queries, write PL/SQL, or wire Oracle into a Spring Data repository, you need a running Oracle 21c instance and a working schema you can connect to from IntelliJ. This is what Part 1 sets up.

Part 1 ends when you have clicked **Test Connection** in IntelliJ and seen a green checkmark. Part 2 covers what to do with that connection (creating tables, loading data, exploring the database).

There are **two versions** of Part 1, depending on what Oracle you are using:

- **Version A: VM-installed Oracle.** Use this if the Oracle 21c XE installation on your VM is working. Steps walk through SQL\*Plus to verify the instance, create a user, and connect IntelliJ.
- **Version B: Oracle 21 in Docker.** Use this if the VM-installed Oracle is broken or you would rather use a clean containerised setup. Steps walk through a single `docker run` command that starts Oracle with a pre-created user, then connect IntelliJ.

Both versions produce the same end state: an Oracle 21c PDB named `XEPDB1` with a user `labuser` (password `labpass123`) that has the permissions to do everything in Part 2. Once you have completed either version, Part 2 is identical regardless of which path you took.

You only need to do one. Read the "Choosing Your Setup Path" section below to decide.

---

## Background - Oracle for C# / SQL Server Developers

Oracle 21c and SQL Server share the same relational foundations, but the terminology and tooling differ in important ways. The table below maps the concepts you already know to their Oracle equivalents.

| SQL Server Concept | Oracle Equivalent | Key Difference |
|--------------------|-------------------|----------------|
| `SSMS / sqlcmd` | `SQL*Plus / SQLcl` | SQL\*Plus is the classic CLI; SQLcl is a modern alternative. IntelliJ replaces SSMS for GUI work. |
| Database | Pluggable Database (PDB) | Oracle 21c XE has one CDB and one PDB named `XEPDB1` by default. |
| Schema / Owner | User (Schema) | In Oracle, a user **is** a schema. Creating a user creates its namespace. |
| `IDENTITY` column | `GENERATED AS IDENTITY` | Same concept, different syntax (added in Oracle 12c). |
| `nvarchar / varchar` | `VARCHAR2` | Oracle `VARCHAR2` is the standard string type; avoid `CHAR` for variable-length data. |
| `getdate()` | `SYSDATE / SYSTIMESTAMP` | `SYSDATE` returns date+time; use `SYSTIMESTAMP` for millisecond precision. |
| `GO` (batch separator) | `/` (forward slash) | A lone `/` on its own line executes the current buffer in SQL\*Plus. |
| `BEGIN...END` (T-SQL) | `BEGIN...END` (PL/SQL) | Syntax is similar but PL/SQL has `DECLARE` sections and uses `:=` for assignment. |

---

## Understanding the Oracle 21c Architecture

Before connecting to Oracle for the first time, it helps to understand what you are actually connecting to. Oracle 21c uses a two-layer architecture that is quite different from SQL Server, and knowing this upfront will prevent a lot of confusion as you work through the labs. **This applies to both Version A and Version B** below.

### The Container Database (CDB)

When Oracle 21c is installed, it creates a single **Container Database** or CDB. Think of this as the Oracle engine itself - it manages memory, background processes, disk I/O, and all the core database infrastructure. There is only one CDB per Oracle installation and it runs everything underneath.

You connect to the CDB root when you log in as SYS. From there you can see the overall state of the database engine, start and stop the instance, and manage the pluggable databases that live inside it. However, the CDB root is not where application data lives - it is an administrative layer, not a workspace.

### The Pluggable Database (PDB)

Inside the CDB sits one or more **Pluggable Databases** or PDBs. Each PDB behaves like a completely self-contained database from the perspective of anyone connecting to it. It has its own users, schemas, tables, tablespaces, and data files. Users connected to one PDB have no visibility into any other PDB.

Your Oracle 21c XE installation ships with one PDB named **XEPDB1**. This is where all your lab work happens. Every table you create, every user you define, and every query you run will live inside XEPDB1.

A useful way to think about the relationship:

| Layer | What it is | SQL Server equivalent |
|-------|------------|-----------------------|
| CDB | The Oracle engine and infrastructure | The SQL Server instance |
| PDB (XEPDB1) | Your working database | A database within that instance |
| labuser | Your schema inside the PDB | A schema owner within the database |

### PDB$SEED

You will also see a second entry called **PDB$SEED** when you query the list of pluggable databases. This is a locked, read-only template that Oracle uses internally when creating new PDBs. You will never connect to it or use it directly - you can ignore it.

### Why This Matters for Your Connections

This architecture explains something that catches most SQL Server developers off guard when they first use Oracle. If you connect without specifying a service name, like this:

```sql
sqlplus labuser/labpass123
```

Oracle will try to authenticate you against the CDB root, which has never heard of `labuser`. The user does not exist there - it only exists inside XEPDB1. You will get an ORA-01017 invalid credentials error even though the username and password are correct.

You must always include the service name in your connection string to land in the right PDB:

```sql
sqlplus labuser/labpass123@localhost/XEPDB1
```

The same rule applies to your JDBC connection string in IntelliJ and later in your Spring Boot configuration. The `XEPDB1` service name is not optional - it is what routes your connection to the correct pluggable database.

---

## Choosing Your Setup Path

Use this guide to decide which version to follow:

| Situation | Use this version |
|-----------|------------------|
| Oracle 21c XE was installed on your VM and starts correctly | Version A (VM-installed) |
| The VM-installed Oracle fails to start, has corrupted listener configuration, or you are getting ORA-12541 or ORA-12514 errors | Version B (Docker) |
| You want the fastest path to a working environment and do not need to interact with the existing Oracle installation | Version B (Docker) |
| You want to learn SQL\*Plus alongside the database | Version A (VM-installed) |

If you started with Version A and ran into installation problems, switch to Version B. You will not lose any work because nothing in Part 2 depends on which path you took to get a connection.

---

# Version A: VM-Installed Oracle

> **Skip this section if you are using Docker.** Jump to **Version B** below.

This version assumes Oracle 21c XE is already installed on your Windows VM and the Windows services for `OracleServiceXE` and `OracleOraDB21Home1TNSListener` are running. If either service is not running, start them from the Windows Services console (`services.msc`) before continuing.

### Step A1 - Open a Command Prompt and Log In

Open a Windows **Command Prompt** (not PowerShell - SQL\*Plus behaves more predictably in CMD).

```sql
sqlplus sys/password as sysdba
```

You should see the `SQL>` prompt. If you see **"Connected to an idle instance"**, start the database first:

```sql
STARTUP
```

> **Note:** `STARTUP` will mount and open the database in one command. Wait until you see `Database opened.` before proceeding.

If `sqlplus` is not found on the PATH, the Oracle client install is incomplete. This is the kind of problem Version B (Docker) is meant to bypass - consider switching paths.

### Step A2 - Verify the Instance and Check the PDB

Run the following queries to confirm what you are connected to:

```sql
SELECT instance_name, status, version FROM v$instance;
```

```sql
SELECT name, open_mode FROM v$pdbs;
```

You should see `XEPDB1` listed with `OPEN_MODE = READ WRITE`. If it shows `MOUNTED`, open it:

```sql
ALTER PLUGGABLE DATABASE XEPDB1 OPEN;
```

### Step A3 - Create a Lab Schema (User)

In Oracle, creating a user is the same as creating a schema namespace. All objects you create as that user live in that schema.

First, switch your session to the PDB:

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
```

Now create the lab user and grant it the permissions it needs:

```sql
CREATE USER labuser IDENTIFIED BY labpass123
DEFAULT TABLESPACE USERS
TEMPORARY TABLESPACE TEMP
QUOTA UNLIMITED ON USERS;
```

```sql
GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER TO labuser;
```

Quickly verify the user can connect:

```sql
CONNECT labuser/labpass123@localhost/XEPDB1
```

You should still see the `SQL>` prompt. Run `SHOW USER` and you should see `USER is "LABUSER"`. Exit SQL\*Plus:

```sql
EXIT
```

> **Tip:** `DUAL` is Oracle's built-in single-row dummy table. Use it whenever you need to evaluate an expression without querying a real table - the Oracle equivalent of `SELECT getdate()` in T-SQL. You will use it heavily in Part 2.

You are now ready to connect IntelliJ. **Skip the Version B section below and go to "Connecting IntelliJ to Oracle".**

---

# Version B: Oracle 21 in Docker

> **Skip this section if you are using the VM-installed Oracle.** You already finished Version A above - jump to **Connecting IntelliJ to Oracle**.

This version uses the community-maintained `gvenzl/oracle-xe:21-slim` Docker image, which is the standard way to run Oracle 21c XE in a container. It pulls from Docker Hub with no login required, starts in about 90 seconds, and auto-creates the lab user for you. You will not need SQL\*Plus on the host at all - everything happens through Docker and IntelliJ.

### Step B1 - Verify Docker is Available

Open a terminal (PowerShell or CMD on Windows, Terminal on macOS/Linux) and confirm Docker is running:

```bash
docker --version
docker ps
```

`docker --version` should report a version number. `docker ps` should run without errors (showing either an empty list or any other containers you have running). If you get a "Cannot connect to the Docker daemon" error, start Docker Desktop and wait for it to finish initialising before continuing.

### Step B2 - Pull the Oracle 21c XE Image

```bash
docker pull gvenzl/oracle-xe:21-slim
```

This downloads the image, which is around 2 GB. Pulling takes a few minutes on a typical connection. You only pay this cost once - subsequent containers reuse the cached image.

### Step B3 - Create a Named Volume for Database Files

A named volume lets the database files survive container removal. Without it, every `docker rm` of the container would wipe your tables and you would have to recreate them.

```bash
docker volume create oracle-lab-data
```

You should see the volume name echoed back. Confirm it exists:

```bash
docker volume ls
```

### Step B4 - Start the Oracle Container

Run the container with the configuration the lab needs:

```bash
docker run -d --name oracle-lab ^
  -p 1522:1521 ^
  -e ORACLE_PASSWORD=password ^
  -e APP_USER=labuser ^
  -e APP_USER_PASSWORD=labpass123 ^
  -v oracle-lab-data:/opt/oracle/oradata ^
  gvenzl/oracle-xe:21-slim
```

> **Note on line continuation:** the `^` characters above are Windows CMD line continuations. If you are on PowerShell, replace each `^` with a backtick (`` ` ``). If you are on macOS or Linux, replace each `^` with a backslash (`\`). Or just paste it all on one line - all forms are equivalent.

What each option does:

| Option | Purpose |
|--------|---------|
| `-d` | Detached mode - the container runs in the background |
| `--name oracle-lab` | Names the container so you can reference it later (`docker logs oracle-lab`, `docker stop oracle-lab`) |
| `-p 1522:1521` | Maps host port **1522** to the container's Oracle listener on port 1521. We use 1522 to avoid conflicting with any other Oracle installation that may still be running on the default port 1521. |
| `-e ORACLE_PASSWORD=password` | Sets the SYS and SYSTEM password to `password`. You will not normally need this for the lab but you may need it later for administrative tasks. |
| `-e APP_USER=labuser` and `APP_USER_PASSWORD=labpass123` | Tells the image to create a non-SYS user named `labuser` with password `labpass123` and the permissions needed for application development. **This replaces Step A3 from the VM-installed version.** |
| `-v oracle-lab-data:/opt/oracle/oradata` | Mounts the named volume you created in Step B3 to the directory where Oracle stores its data files. Your tables and data will survive container removal. |

### Step B5 - Wait for Oracle to Finish Starting

Oracle takes 60-90 seconds to fully start the first time, and even longer on a slow VM. The container will show as "running" within seconds, but Oracle inside is not ready to accept connections until it has finished its full startup sequence.

Watch the startup progress with:

```bash
docker logs -f oracle-lab
```

You will see a lot of output. The container is ready when you see this line near the end:

```
DATABASE IS READY TO USE!
```

Press `Ctrl+C` to stop following the logs once you see it.

Alternative: use the container's healthcheck. After a successful startup, `docker ps` shows the container status with `(healthy)`:

```bash
docker ps
```

```
CONTAINER ID  IMAGE                       STATUS                  PORTS                    NAMES
abc123def456  gvenzl/oracle-xe:21-slim    Up 2 minutes (healthy)  0.0.0.0:1522->1521/tcp  oracle-lab
```

Until you see `(healthy)` or `DATABASE IS READY TO USE!`, IntelliJ's Test Connection will fail with a network error. This is normal and just means you got there first - wait another 30 seconds and try again.

### Step B6 - Understand What You Have

The container is now running Oracle 21c XE with the following setup:

- A CDB (the Oracle engine, same as the VM-installed version)
- A PDB called `XEPDB1`
- A user called `labuser` with password `labpass123`, already created with the permissions for `CREATE TABLE`, `CREATE SEQUENCE`, `CREATE PROCEDURE`, and `CREATE TRIGGER`
- A SYS user with password `password` (set by `ORACLE_PASSWORD`)
- All data files stored in the `oracle-lab-data` volume

You did not have to run `CREATE USER` because the image's startup script did it for you when it saw the `APP_USER` and `APP_USER_PASSWORD` environment variables. The end state is identical to what Version A produces by hand.

### Container Management Cheat Sheet

For reference, here are the commands you will use to manage the container during this and later labs:

| Action | Command |
|--------|---------|
| Stop the container (keeps data, can restart later) | `docker stop oracle-lab` |
| Start it again | `docker start oracle-lab` |
| Remove the container (keeps data in the volume) | `docker stop oracle-lab && docker rm oracle-lab` |
| Recreate it (after `docker rm`) | Re-run the `docker run` command from Step B4 |
| Watch the logs | `docker logs -f oracle-lab` |
| See if it is healthy | `docker ps` |
| Run SQL\*Plus inside the container (optional, if you want it) | `docker exec -it oracle-lab sqlplus labuser/labpass123@localhost/XEPDB1` |
| Destroy data permanently | `docker volume rm oracle-lab-data` |

You are now ready to connect IntelliJ. Continue to the next section.

---

# Connecting IntelliJ to Oracle

This section is the same for both versions. The only difference is the port number you enter: **1521** for Version A (VM-installed) or **1522** for Version B (Docker).

IntelliJ IDEA Ultimate includes a full-featured database console that replaces SSMS for Oracle work. Once connected, you can browse schemas, run SQL, view execution plans, and export results.

### Step 1 - Open the Database Tool Window

- In IntelliJ, go to **View -> Tool Windows -> Database** (or press the Database icon in the right-hand sidebar).
- Click the **+** button -> **Data Source -> Oracle**.

### Step 2 - Configure the Connection

Fill in the connection dialog as follows:

| Field | Version A (VM-installed) | Version B (Docker) |
|-------|--------------------------|---------------------|
| Host | `localhost` | `localhost` |
| Port | `1521` | **`1522`** |
| Connection type | **Service Name** (not SID) | **Service Name** (not SID) |
| Service Name | `XEPDB1` | `XEPDB1` |
| User | `labuser` | `labuser` |
| Password | `labpass123` | `labpass123` |
| Driver | Oracle (download automatically if prompted) | Oracle (download automatically if prompted) |

The first time you configure an Oracle connection, IntelliJ will prompt you to download the Oracle JDBC driver. Click **Download** and wait for it to finish - this happens once per IntelliJ installation.

Click **Test Connection**. You should see a green checkmark and "Successful".

> **Critical:** Make sure you select **Service Name**, not SID, in the connection type dropdown. `XEPDB1` is a service name. Using SID will try to connect to the root CDB (named `XE`), which does not have `labuser` defined and will reject your credentials with an ORA-01017 error.

Click **OK** to save the connection.

### Troubleshooting Test Connection Failures

| Error | Likely cause | Fix |
|-------|--------------|-----|
| `ORA-12541: TNS:no listener` (Version A) | Oracle services not running | Open `services.msc`, start `OracleServiceXE` and the listener |
| `IO Error: Connection refused` (Version B) | Container not yet ready | Run `docker logs -f oracle-lab` and wait for `DATABASE IS READY TO USE!` |
| `ORA-12514: TNS:listener does not currently know of service` | Wrong service name or PDB not open | Confirm Service Name is `XEPDB1` (case sensitive on some systems). For Version A, log in as SYS via SQL\*Plus and run `ALTER PLUGGABLE DATABASE XEPDB1 OPEN;` |
| `ORA-01017: invalid username/password` | Wrong credentials, OR Connection type set to SID instead of Service Name | Verify `labuser` / `labpass123`. Change Connection type dropdown to Service Name. |
| `IO Error: The Network Adapter could not establish the connection` (Version B) | Port mismatch - container is on 1522 but IntelliJ is trying 1521, or vice versa | Confirm `docker ps` shows `0.0.0.0:1522->1521/tcp` and IntelliJ's port field is set to 1522 |

If `Test Connection` succeeds, you are done with Part 1. Proceed to **Part 2: Oracle Navigation and Querying**.

---

## Part 1 Summary

You have completed one of two setup paths and have a working IntelliJ connection to Oracle 21c. Specifically:

- An Oracle 21c instance is running (either as a Windows service on your VM, or as a Docker container named `oracle-lab`)
- The PDB `XEPDB1` is open and accepting connections
- A user `labuser` with password `labpass123` exists with the permissions needed for the rest of the lab series
- IntelliJ's Data Source tool can successfully connect to the database

Part 2 picks up from here and is identical regardless of which version of Part 1 you completed.
