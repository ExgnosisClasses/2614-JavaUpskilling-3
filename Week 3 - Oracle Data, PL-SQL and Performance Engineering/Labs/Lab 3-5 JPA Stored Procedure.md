# Lab 3.5 - Calling Oracle Stored Procedures from Spring Boot JPA

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**
**Module 5 | Estimated time: 45-60 minutes | Tools: IntelliJ IDEA Ultimate, Oracle 21c XE**

---

## Overview

This lab adds an Oracle stored procedure to an existing Spring Boot JPA application and calls it from Java. The domain is the help desk ticketing system from Lab 3.4: departments and tickets. The procedure counts open tickets for a given department. The lab is focused entirely on the stored procedure call pattern and nothing else.

By the end of this lab you will have:

- Defined a PL/SQL stored procedure with an IN parameter and an OUT parameter in Oracle
- Called the procedure from a Spring service using `@NamedStoredProcedureQuery` and the JPA `EntityManager`
- Exposed the result through a single REST endpoint
- Understood what happens at the JDBC level when JPA calls a stored procedure

---

## Before You Start

This lab requires an Oracle schema with `DEPARTMENTS` and `TICKETS` tables and sample data. If you completed Lab 3.4 those tables already exist in `XEPDB1` under `labuser`.

Connect as labuser and confirm the tables are present:

```sql
sqlplus labuser/labpass123@localhost/XEPDB1
```

```sql
SELECT table_name FROM user_tables
WHERE  table_name IN ('DEPARTMENTS', 'TICKETS')
ORDER  BY table_name;
```

Expected output:

```
TABLE_NAME
----------
DEPARTMENTS
TICKETS
```

If neither table is present, run the DDL and sample data inserts from Lab 3.4 Steps 1.2 through 1.4 before continuing.

---

## Part 1 - Create the Spring Boot Project

### Step 1.1 - Generate the project from Spring Initializr

Open [https://start.spring.io](https://start.spring.io) and configure as follows:

| Setting | Value |
|---------|-------|
| Project | Maven |
| Language | Java |
| Spring Boot | Latest stable 3.x |
| Group | `com.example` |
| Artifact | `procdemo` |
| Packaging | Jar |
| Java | 17 |

Add the following dependencies:

- **Spring Web**
- **Spring Data JPA**
- **Oracle Driver**

Click **Generate**, unzip the archive, and open the project in IntelliJ via **File -> Open -> New Window**.

Wait for Maven to finish downloading dependencies before continuing.

### Step 1.2 - Configure the datasource

Rename `application.properties` to `application.yaml` using **Refactor -> Rename** in the IntelliJ Project panel.

Open `application.yaml` and add:

```yaml
spring:
  datasource:
    url: jdbc:oracle:thin:@localhost:1521/XEPDB1
    username: labuser
    password: labpass123
    driver-class-name: oracle.jdbc.OracleDriver

  jpa:
    hibernate:
      ddl-auto: validate
    show-sql: true
    properties:
      hibernate:
        format_sql: true
```

`ddl-auto: validate` tells Hibernate to check that the tables exist and match the entity classes at startup. It will not create or modify anything. `show-sql: true` prints every SQL statement to the console, including the stored procedure call.

### Step 1.3 - Create the package structure

Right-click `src/main/java/com/example/procdemo` in the Project panel and create these sub-packages:

```
com.example.procdemo
├── controller
├── entity
└── service
```

---

## Part 2 - Define the Stored Procedure in Oracle

### Step 2.1 - Understand what the procedure will do

The procedure is named `GET_OPEN_TICKET_COUNT`. It accepts one input parameter (a department ID) and returns one output parameter (the count of tickets in that department with status `OPEN`). This is the simplest meaningful procedure: one IN, one OUT, one SQL statement inside.

### Step 2.2 - Create the procedure

Still connected as labuser in SQL*Plus:

```sql
CREATE OR REPLACE PROCEDURE get_open_ticket_count (
    p_department_id  IN  NUMBER,
    p_open_count     OUT NUMBER
)
AS
BEGIN
    SELECT COUNT(*)
    INTO   p_open_count
    FROM   tickets
    WHERE  department_id = p_department_id
    AND    status        = 'OPEN';
END get_open_ticket_count;
/
```

Confirm it compiled successfully:

```sql
SELECT object_name, status
FROM   user_objects
WHERE  object_name = 'GET_OPEN_TICKET_COUNT';
```

Expected output:

```
OBJECT_NAME              STATUS
------------------------ -------
GET_OPEN_TICKET_COUNT    VALID
```

If `STATUS` shows `INVALID`, run `SHOW ERRORS` to see the details.

### Step 2.3 - Test the procedure manually

Before writing any Java, confirm the procedure returns the correct result directly in SQL*Plus:

```sql
SET SERVEROUTPUT ON;

DECLARE
    v_count NUMBER;
BEGIN
    get_open_ticket_count(
        p_department_id => 1,
        p_open_count    => v_count
    );
    DBMS_OUTPUT.PUT_LINE('Open tickets for dept 1: ' || v_count);
END;
/
```

Based on the Lab 3.4 sample data, department 1 (Infrastructure) has 2 open tickets. You should see:

```
Open tickets for dept 1: 2
```

Repeat for department IDs 2 and 3 to confirm all return expected values. Only proceed to the Java code once the procedure is confirmed working at the database level.

---

## Part 3 - Map the Entity and Declare the Stored Procedure

JPA calls stored procedures through the `StoredProcedureQuery` API. The procedure is declared on a JPA entity using `@NamedStoredProcedureQuery`. This annotation registers the procedure name, its parameters, and their types so that JPA can call it through the `EntityManager`.

### Step 3.1 - Create the Department entity

Create `Department.java` in the `entity` package:

```java
package com.example.procdemo.entity;

import jakarta.persistence.*;

// @NamedStoredProcedureQuery registers the Oracle stored procedure with JPA.
// name:          the logical name used in Java code to look up this declaration
// procedureName: the exact name of the procedure in Oracle
// parameters:    declares each parameter with its name, mode (IN/OUT), and Java type
//
// The parameter names here ("p_department_id", "p_open_count") must match
// the parameter names declared in the PL/SQL procedure exactly.
@NamedStoredProcedureQuery(
        name = "Department.getOpenTicketCount",
        procedureName = "get_open_ticket_count",
        parameters = {
                @StoredProcedureParameter(
                        name = "p_department_id",
                        mode = ParameterMode.IN,
                        type = Long.class
                ),
                @StoredProcedureParameter(
                        name = "p_open_count",
                        mode = ParameterMode.OUT,
                        type = Long.class
                )
        }
)
@Entity
@Table(name = "departments")
public class Department {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "department_id")
    private Long departmentId;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "location", length = 100)
    private String location;

    public Long getDepartmentId() { return departmentId; }
    public String getName() { return name; }
    public String getLocation() { return location; }
}
```

> **Why the annotation lives on the entity:** JPA's `@NamedStoredProcedureQuery` must be placed on an entity class. It is associated with the `Department` entity here because the procedure operates on ticket data that belongs to departments. The entity does not need to have any direct relationship to the procedure's output. The annotation is simply a named registration that the `EntityManager` can look up at runtime.

> **Why `Long.class` for both parameters:** The Oracle `NUMBER` type maps to `Long` in Java for whole-number values. The IN parameter sends a `Long` department ID. The OUT parameter receives the count as a `Long`. Using `Integer.class` would also work but `Long` is safer for Oracle `NUMBER` columns which can exceed `Integer` range.

---

## Part 4 - Call the Procedure from the Service Layer

### Step 4.1 - Create TicketService

Create `TicketService.java` in the `service` package:

```java
package com.example.procdemo.service;

import jakarta.persistence.EntityManager;
import jakarta.persistence.StoredProcedureQuery;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TicketService {

    private final EntityManager entityManager;

    // EntityManager is the JPA session through which all database operations run.
    // Spring injects it automatically when declared as a constructor parameter.
    public TicketService(EntityManager entityManager) {
        this.entityManager = entityManager;
    }

    @Transactional(readOnly = true)
    public long getOpenTicketCount(Long departmentId) {

        // Look up the named stored procedure declaration registered on Department.
        // "Department.getOpenTicketCount" is the logical name from the
        // @NamedStoredProcedureQuery annotation on the Department entity.
        StoredProcedureQuery query = entityManager
                .createNamedStoredProcedureQuery("Department.getOpenTicketCount");

        // Bind the IN parameter by the name declared in the annotation.
        query.setParameter("p_department_id", departmentId);

        // execute() sends the call to Oracle.
        // Internally JPA uses a JDBC CallableStatement: {call get_open_ticket_count(?, ?)}
        // Oracle runs the procedure and populates the OUT parameter.
        query.execute();

        // Read the OUT parameter by name.
        // The value is returned as the declared type (Long.class).
        Long count = (Long) query.getOutputParameterValue("p_open_count");
        return count != null ? count : 0L;
    }
}
```

**Three lines do all the work:**

`createNamedStoredProcedureQuery` finds the `@NamedStoredProcedureQuery` declaration by its logical name and prepares a `CallableStatement` against Oracle.

`setParameter` binds the department ID to the IN parameter. JPA uses the parameter name declared in `@StoredProcedureParameter`, not a positional index.

`execute` runs the procedure. Oracle executes `GET_OPEN_TICKET_COUNT` and writes the result into `p_open_count`.

`getOutputParameterValue` reads the OUT parameter value back from the `CallableStatement` after execution.

---

## Part 5 - Expose the Result Through a Controller

### Step 5.1 - Create TicketController

Create `TicketController.java` in the `controller` package:

```java
package com.example.procdemo.controller;

import com.example.procdemo.service.TicketService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/departments")
public class TicketController {

    private final TicketService ticketService;

    public TicketController(TicketService ticketService) {
        this.ticketService = ticketService;
    }

    @GetMapping("/{id}/open-ticket-count")
    public ResponseEntity<Map<String, Object>> getOpenTicketCount(
            @PathVariable Long id) {

        long count = ticketService.getOpenTicketCount(id);

        // Return a simple JSON object with the department ID and the count.
        // A dedicated DTO class would be appropriate in a larger application.
        return ResponseEntity.ok(Map.of(
                "departmentId", id,
                "openTicketCount", count
        ));
    }
}
```

---

## Part 6 - Run and Test

### Step 6.1 - Start the application

Run `ProcdemoApplication.java`. Watch the startup log. Hibernate will validate the `DEPARTMENTS` table against the `Department` entity at startup. You should see:

```
SchemaValidator - Validated schema for table [departments]
Started ProcdemoApplication in X.XXX seconds
```

If you see a `SchemaManagementException`, a column name in the entity does not match the Oracle column. Compare the `@Column` annotations against the DDL from Lab 3.4.

### Step 6.2 - Create an HTTP test file

Create `procdemo-tests.http` in the project root:

```http
### Count open tickets for department 1 (Infrastructure - expect 2)
GET http://localhost:8080/api/v1/departments/1/open-ticket-count

###

### Count open tickets for department 2 (Application Support - expect 1)
GET http://localhost:8080/api/v1/departments/2/open-ticket-count

###

### Count open tickets for department 3 (Security - expect 1)
GET http://localhost:8080/api/v1/departments/3/open-ticket-count

###

### Non-existent department - Oracle returns 0 for COUNT(*) with no matching rows
GET http://localhost:8080/api/v1/departments/999/open-ticket-count
```

### Step 6.3 - Execute and observe

Run the request for department 1. The response should be:

```json
{
  "openTicketCount": 2,
  "departmentId": 1
}
```

Watch the IntelliJ console while the request executes. You will see a SQL statement from Hibernate that looks like this:

```sql
{call get_open_ticket_count(?, ?)}
```

This is the JDBC escape syntax for stored procedure calls. JPA generates it automatically from the `@NamedStoredProcedureQuery` declaration. The first `?` is the IN parameter (`p_department_id`). The second `?` is the OUT parameter (`p_open_count`). You did not write this syntax yourself.

Run the requests for departments 2 and 3 and verify the counts match. Run the request for department 999. The procedure executes a `COUNT(*)` query with `WHERE department_id = 999`. Because no tickets exist for that department, Oracle returns 0. No exception is thrown. The response will be:

```json
{
  "openTicketCount": 0,
  "departmentId": 999
}
```

---

## Checkpoints

Answer these before closing the lab.

1. The `@NamedStoredProcedureQuery` annotation is placed on the `Department` entity even though the procedure queries the `TICKETS` table. JPA requires this annotation to be on an entity. Why does it not matter which entity it lives on, and what would happen if you placed an identical annotation on a second entity with the same logical name?

2. The service method is annotated with `@Transactional(readOnly = true)`. A stored procedure call is not a query in the JDBC sense. Why is a transaction still required, and what does `readOnly = true` tell the transaction manager in this context?

3. `query.execute()` sends `{call get_open_ticket_count(?, ?)}` to Oracle. Compare this to how `@Query` methods in a JPA repository send SQL to Oracle. What is fundamentally different about the way Oracle processes these two types of statements?

4. `getOutputParameterValue("p_open_count")` returns a `Long`. What would happen if you cast it to `Integer` instead? What does that tell you about how JPA honours the `type = Long.class` declaration in the `@StoredProcedureParameter` annotation?

5. The procedure returns 0 for a department ID that does not exist, rather than throwing an exception. In a production application, should the controller return `200 OK` with a count of 0 for a non-existent department, or `404 Not Found`? What change would you make to the service layer to implement the 404 behaviour?

---

## Lab Summary

In this lab you:

- Created a minimal Spring Boot JPA project connected to the existing `XEPDB1` Oracle database
- Defined a PL/SQL stored procedure with one IN and one OUT parameter and verified it in SQL*Plus before writing any Java
- Registered the procedure with JPA using `@NamedStoredProcedureQuery` on the `Department` entity
- Called the procedure from a service method using `EntityManager.createNamedStoredProcedureQuery`, `setParameter`, `execute`, and `getOutputParameterValue`
- Observed the `{call ...}` JDBC escape syntax that JPA generates in the console log
- Exposed the result through a REST endpoint and confirmed the counts match the Oracle data

---

*End of Lab 3.5*
