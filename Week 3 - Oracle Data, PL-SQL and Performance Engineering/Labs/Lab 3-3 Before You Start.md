# Lab 3-3 Setup S


---

## Before You Start lab 3-3

Work through the checks in this section before opening any code. Pick **one** of the two setup versions below depending on which Oracle environment you are using:

- **Version A - VM-Installed Oracle.** Use this if you set up Oracle directly on your VM and have SQL*Plus available.
- **Version B - Oracle in a Docker Container.** Use this if you completed Lab 3.0 Part 1 Version B and have the `oracle-lab` container.

Both versions get you to the same end state: a working IntelliJ connection as `labuser` to the `XEPDB1` pluggable database, with a clean schema and no leftover lab tables. After you finish your chosen version, complete the **IntelliJ Edition Check** at the end of this section. Then proceed to Part 1.

> **One-time decision:** stick with whichever version you used for the previous labs. Mixing setups mid-course leads to confusion about which database your IntelliJ connection is talking to. If you need to switch, do a clean break: detach the old data source in IntelliJ before adding a new one.

---

# Version A - VM-Installed Oracle

> **Skip this section if you are using Docker.** Jump to **Version B** below.

Work through the steps in order. Each step includes the exact command to run and the output you should expect. Do not move on to Part 1 until every check passes.

### Check A1 - Open a Command Prompt and start SQL*Plus as SYS

Open a Windows **Command Prompt** (use CMD, not PowerShell).

```sql
sqlplus sys/password as sysdba
```

You should see the `SQL>` prompt. If you see **"Connected to an idle instance"**, the database is not running. Start it now:

```sql
STARTUP
```

Wait until you see `Database opened.` before continuing.

> **Note:** `STARTUP` mounts and opens the database in one step. It can take 30-60 seconds on a lab machine.

### Check A2 - Confirm the Oracle instance is running

At the `SQL>` prompt:

```sql
SELECT instance_name, status, version FROM v$instance;
```

Expected output:

```
INSTANCE_NAME    STATUS       VERSION
---------------- ------------ -----------------
xe               OPEN         21.0.0.0.0
```

If `STATUS` shows anything other than `OPEN`, something is wrong with the Oracle installation. Ask your instructor before continuing.

### Check A3 - Confirm XEPDB1 is open

```sql
SELECT name, open_mode FROM v$pdbs;
```

Expected output:

```
NAME        OPEN_MODE
----------- ----------
PDB$SEED    READ ONLY
XEPDB1      READ WRITE
```

If `XEPDB1` shows `MOUNTED` instead of `READ WRITE`, open it:

```sql
ALTER PLUGGABLE DATABASE XEPDB1 OPEN;
```

Run the SELECT again and confirm `OPEN_MODE` is now `READ WRITE`.

### Check A4 - Switch your session into XEPDB1

You are currently connected to the CDB root (the engine layer). Switch into the pluggable database where the lab user lives:

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
```

Expected output:

```
Session altered.
```

### Check A5 - Confirm labuser exists

```sql
SELECT username, account_status FROM dba_users WHERE username = 'LABUSER';
```

Expected output:

```
USERNAME    ACCOUNT_STATUS
----------- ----------------
LABUSER     OPEN
```

If you see **no rows returned**, the lab user has not been created yet. Run the following to create it, then recheck:

```sql
CREATE USER labuser IDENTIFIED BY labpass123
DEFAULT TABLESPACE USERS
TEMPORARY TABLESPACE TEMP
QUOTA UNLIMITED ON USERS;

GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE,
      CREATE PROCEDURE, CREATE TRIGGER TO labuser;
```

If you see `ACCOUNT_STATUS = LOCKED`, unlock it:

```sql
ALTER USER labuser ACCOUNT UNLOCK;
```

### Check A6 - Confirm labuser can connect to XEPDB1

Either open a **second** Command Prompt window and connect as labuser directly. If you take this option, you can close the window where you logged in as SYS - you do not need to be connected as SYS for the rest of the lab.

```sql
sqlplus labuser/labpass123@localhost/XEPDB1
```

Or use the connect command from previous labs in the same window where you logged in as SYS:

```sql
CONNECT labuser/labpass123@localhost/XEPDB1
```

```
Connected to:
Oracle Database 21c Express Edition ...

SQL>
```

Confirm you are in the right container and connected as the right user:

```sql
SHOW USER
```

```
USER is "LABUSER"
```

```sql
SELECT sys_context('USERENV', 'CON_NAME') AS container FROM dual;
```

```
CONTAINER
---------
XEPDB1
```

Both must be correct. If the connection fails with `ORA-01017: invalid username/password`, the password is wrong or the user does not exist in XEPDB1. Return to Check A5 and verify the user was created inside XEPDB1, not in the CDB root.

> **Note:** The `/XEPDB1` at the end of the connect string is not optional. Without it, Oracle attempts to authenticate against the CDB root, which has no knowledge of `labuser`.

### Check A7 - Confirm the lab tables do not already exist

Still connected as labuser:

```sql
SELECT table_name FROM user_tables ORDER BY table_name;
```

If the output shows `CATEGORIES` and `PRODUCTS` already present from a previous attempt, drop them before running the DDL in Part 1:

```sql
DROP TABLE products;
DROP TABLE categories;
```

The `products` table must be dropped first because it holds the foreign key that references `categories`. If you drop `categories` first, Oracle returns `ORA-02449: unique/primary keys in table referenced by foreign keys`. If the output shows no rows, the schema is clean and you are ready to proceed.

You can also keep tables from Lab 3.0 (`CUSTOMERS`, `ACCOUNTS`, `TRANSACTIONS`) and Lab 3.2 (any `PL_*` tables) - they do not interfere with this lab.

### Version A connection summary for IntelliJ

When you reach Part 2 and configure the Spring Boot datasource, use these values for the VM-installed Oracle:

| Setting | Value |
|---------|-------|
| Host | `localhost` |
| Port | `1521` |
| Service Name | `XEPDB1` |
| User | `labuser` |
| Password | `labpass123` |

JDBC URL form: `jdbc:oracle:thin:@localhost:1521/XEPDB1`

You can close all SQL*Plus windows. The rest of the lab happens in IntelliJ. Skip the Version B section below and continue to the **IntelliJ Edition Check** at the end of this section.

---

# Version B - Oracle in a Docker Container

> **Skip this section if you are using the VM-installed Oracle.** You already finished Version A above - jump to the **IntelliJ Edition Check** at the end of this section.

This version assumes you completed Lab 3.0 Part 1 Version B and have the `oracle-lab` container set up. Since the Docker setup skipped SQL*Plus entirely, all checks here are run from a terminal (for container status) and from IntelliJ (for database access).

### Check B1 - Confirm Docker is running

Open a terminal (PowerShell or CMD on Windows, Terminal on macOS/Linux):

```bash
docker --version
docker ps
```

`docker --version` should report a version number. `docker ps` should run without errors. If you get "Cannot connect to the Docker daemon", start Docker Desktop and wait for it to finish initialising before continuing.

### Check B2 - Confirm the oracle-lab container exists and is healthy

```bash
docker ps -a --filter "name=oracle-lab"
```

Look at the `STATUS` column. There are four possible states:

| Status | What to do |
|--------|------------|
| `Up <time> (healthy)` | Container is running and Oracle is ready. Proceed to Check B3. |
| `Up <time> (health: starting)` | Container is running but Oracle is still starting. Wait 60-90 seconds and re-run the command until you see `(healthy)`. |
| `Exited (...)` | Container exists but is stopped. See "Container exists but is stopped" below. |
| (no rows returned) | Container does not exist. See "Container does not exist" below. |

**Container exists but is stopped:**

This is the normal state after you shut down your VM or restart your machine. The container is preserved with all your data intact - you just need to start it again. **Do not use `docker run`** for this case. `docker run` creates a new container, which would fail with a name conflict error (`Conflict. The container name "/oracle-lab" is already in use`). The correct command is `docker start`, which restarts the existing container:

```bash
docker start oracle-lab
```

Expected output:

```
oracle-lab
```

Docker just echoes the container name back to you. The container is now starting in the background.

Verify it is actually running:

```bash
docker ps --filter "name=oracle-lab"
```

You should see the container in the output (not just in `docker ps -a`) with a `STATUS` of either `Up <time> (health: starting)` or `Up <time> (healthy)`.

**How long the restart takes:**

A restart is much faster than a first-boot because the datafiles are already on disk in the named volume - Oracle does not need to uncompress them again. Expect:

- 15-30 seconds on a typical lab machine
- Up to 60 seconds on a slow VM

Until the status shows `(healthy)`, IntelliJ's Test Connection will fail with a network error. Re-run `docker ps` every 10-15 seconds until you see the healthy status, or watch the startup live:

```bash
docker logs -f oracle-lab
```

On a restart you will not see the first-boot messages (no "uncompressing database data files"). The log starts at the listener startup and you should see `DATABASE IS READY TO USE!` within 30 seconds or so. Press `Ctrl+C` to stop following the logs once you see it.

**If `docker start` fails:**

| Error | Likely cause | Fix |
|-------|--------------|-----|
| `Error response from daemon: driver failed programming external connectivity ... port is already allocated` | Another process is using port 1522 (often a previous Docker container that did not clean up, or another Oracle instance) | Find the conflict with `docker ps --filter "publish=1522"` and stop that container, or check for non-Docker processes with `netstat -an \| findstr 1522` on Windows or `lsof -i :1522` on macOS/Linux |
| `Error response from daemon: cannot start a stopped container` followed by a volume mount error | The `oracle-lab-data` volume was deleted | Recreate the container from scratch using the "Container does not exist" instructions below. Your data is gone but the lab will still work. |
| Container starts but immediately exits (status shows `Exited (1)` seconds later) | Check `docker logs oracle-lab` for the actual error. Usually a corrupted datafile or out-of-memory condition. | If the logs show datafile corruption, you may need to remove the container and volume and start fresh. Save the log output first - your instructor can use it to diagnose the underlying problem. |

**Container does not exist (or you removed it):**

If `docker ps -a` shows no `oracle-lab` row, recreate the container with the same command from Lab 3.0 Part 1 Version B Step B4. Your data is preserved in the `oracle-lab-data` volume if you created the volume previously:

```bash
docker run -d --name oracle-lab ^
  -p 1522:1521 ^
  -e ORACLE_PASSWORD=password ^
  -e APP_USER=labuser ^
  -e APP_USER_PASSWORD=labpass123 ^
  -v oracle-lab-data:/opt/oracle/oradata ^
  gvenzl/oracle-xe:21-slim
```

(Replace `^` with `` ` `` on PowerShell or `\` on macOS/Linux.) Wait for `(healthy)` status before continuing.

If you also deleted the volume (`docker volume rm oracle-lab-data`), all data from previous labs is gone and you will need to re-run Lab 3.0 Part 2 and Lab 3.2 to recreate it. Tables from earlier labs do not interfere with this lab, so this is optional, but you will not have the `CUSTOMERS`/`ACCOUNTS`/`TRANSACTIONS` tables for reference.

### Check B3 - Confirm IntelliJ can connect to labuser@XEPDB1

Open IntelliJ. If the `labuser` data source from Lab 3.0 or Lab 3.2 is still configured, use it. If not, add one now:

1. Open the **Database** tool window (**View -> Tool Windows -> Database**).
2. Click the **+** button -> **Data Source -> Oracle**.
3. Fill in the connection dialog:

   | Setting | Value |
   |---------|-------|
   | Host | `localhost` |
   | Port | **`1522`** |
   | Connection type | **Service Name** (not SID) |
   | Service Name | `XEPDB1` |
   | User | `labuser` |
   | Password | `labpass123` |

4. If prompted to download the Oracle JDBC driver, click **Download** and wait for it to complete.
5. Click **Test Connection**. You should see a green checkmark and "Successful".

If Test Connection fails:

| Error | Likely cause | Fix |
|-------|--------------|-----|
| `IO Error: Connection refused` | Container not yet healthy | Re-run Check B2 and wait for `(healthy)` |
| `ORA-12514: TNS:listener does not currently know of service` | Wrong service name | Confirm Service Name is `XEPDB1` (case sensitive) |
| `ORA-01017: invalid username/password` | Wrong credentials or wrong connection type | Verify `labuser` / `labpass123` and ensure Connection type is **Service Name**, not SID |
| `Network Adapter could not establish the connection` | Wrong port | Confirm `docker ps` shows `0.0.0.0:1522->1521/tcp` and IntelliJ's Port is `1522` |

### Check B4 - Confirm you are connected to the right user and PDB

Open a new query console for the `labuser` connection (right-click the connection -> **New -> Query Console**). Run:

```sql
SELECT user, sys_context('USERENV', 'CON_NAME') AS container FROM dual;
```

Expected result:

```
USER       CONTAINER
---------- ---------
LABUSER    XEPDB1
```

Both must be correct. If `USER` shows anything other than `LABUSER`, you are connected as a different user - check your connection settings. If `CONTAINER` is not `XEPDB1`, you are connected to the CDB root - go back to Check B3 and confirm Service Name is `XEPDB1`.

### Check B5 - Confirm the lab tables do not already exist

In the same query console:

```sql
SELECT table_name FROM user_tables ORDER BY table_name;
```

If the output shows `CATEGORIES` and `PRODUCTS` already present from a previous attempt, drop them before running the DDL in Part 1:

```sql
DROP TABLE products;
DROP TABLE categories;
```

The `products` table must be dropped first because it holds the foreign key that references `categories`. If you drop `categories` first, Oracle returns `ORA-02449: unique/primary keys in table referenced by foreign keys`. If the output shows no rows, the schema is clean and you are ready to proceed.

You can keep tables from Lab 3.0 (`CUSTOMERS`, `ACCOUNTS`, `TRANSACTIONS`) and Lab 3.2 (any `PL_*` tables) - they do not interfere with this lab.

### Version B connection summary for IntelliJ

When you reach Part 2 and configure the Spring Boot datasource, use these values for the Docker container:

| Setting | Value |
|---------|-------|
| Host | `localhost` |
| Port | **`1522`** |
| Service Name | `XEPDB1` |
| User | `labuser` |
| Password | `labpass123` |

JDBC URL form: `jdbc:oracle:thin:@localhost:1522/XEPDB1`

> **Critical:** the only difference between Version A and Version B for the Spring Boot configuration is the port number - `1521` for VM-installed Oracle, `1522` for the Docker container. Get this wrong and the application will fail to start with a connection-refused error.

Continue to the **IntelliJ Edition Check** below.

---

## IntelliJ Edition Check (Both Versions)

Open IntelliJ. Go to **Help -> About** and confirm the edition shows **IntelliJ IDEA Ultimate**. The Community edition does not include the Oracle JDBC driver download or the built-in database console that this lab uses.

---

## Summary - what a clean environment looks like

| Check | Version A (VM-installed) | Version B (Docker) |
|-------|---------------------------|---------------------|
| Oracle running | `STATUS = OPEN` in `v$instance` | `(healthy)` in `docker ps` |
| XEPDB1 open | `OPEN_MODE = READ WRITE` in `v$pdbs` | Implicit - the image opens XEPDB1 automatically |
| labuser exists | `ACCOUNT_STATUS = OPEN` in `dba_users` | Implicit - created at container startup via `APP_USER` |
| labuser connects | `sqlplus labuser/labpass123@localhost/XEPDB1` succeeds | IntelliJ Test Connection on port **1522** succeeds |
| Schema is clean | No `CATEGORIES` or `PRODUCTS` in `user_tables` | No `CATEGORIES` or `PRODUCTS` in `user_tables` |
| IntelliJ edition | Ultimate (both versions) | Ultimate (both versions) |

All checks must pass before you open IntelliJ and begin Part 1.

---
