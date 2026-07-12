# Lab 3-4: Spring Data JDBC with Oracle

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**
**Module 5 | Estimated time: 90-120 minutes | Tools: IntelliJ IDEA Ultimate, Oracle 21c XE**

---

## Overview

This lab builds a Spring Boot application backed by Spring Data JDBC and Oracle. You will work with a help desk ticketing domain: support departments own tickets, and each ticket belongs to exactly one department. This domain is deliberately different from the product catalog in Lab 3.3 so you can compare the two approaches side by side without domain overlap getting in the way.

Spring Data JDBC takes a fundamentally different position from JPA. Where JPA manages an entity lifecycle and generates SQL invisibly, Spring Data JDBC executes explicit SQL, has no session, and has no lazy loading. Every object you load is a plain Java object with no proxy attached. What you read is exactly what came back from Oracle. Nothing happens to the database unless you call a method that causes it to happen.

By the end of this lab you will have:

- Created a Spring Boot project with Spring Data JDBC, Oracle JDBC, and Web dependencies
- Understood the aggregate root model and how it differs from JPA entity graphs
- Mapped two related Oracle tables to a single aggregate using `@Table`, `@Id`, and `@MappedCollection`
- Configured Spring Data JDBC to work correctly with Oracle identifier casing
- Seen that loading an aggregate always loads the entire object graph in one or two queries, with no lazy loading
- Written explicit SQL using `@Query` and observed that there is no JPQL, no dirty checking, and no managed lifecycle
- Compared every significant behaviour to Lab 3.3 side by side

---

## Spring Data JDBC vs Spring Data JPA - Read This First

Before touching any code, read this comparison. Every difference listed here will appear concretely during the lab. Refer back to this table when you encounter behaviour that surprises you.

| Dimension | Spring Data JDBC | Spring Data JPA |
|-----------|-----------------|-----------------|
| Underlying technology | Spring JdbcTemplate, no ORM | JPA (Hibernate), full ORM |
| Entity lifecycle | None. Objects are plain Java objects. | Managed. Hibernate tracks transient, persistent, detached, removed states. |
| Session / EntityManager | Does not exist. | Required. All managed entities are bound to a session. |
| Dirty checking | Does not exist. You must call `save()` to persist any change. | Automatic. Hibernate detects field changes at flush time and issues UPDATE without an explicit `save()` call. |
| Lazy loading | Does not exist. The aggregate is always loaded in full. | Supported. Related objects are proxied and loaded on first access. |
| N+1 query problem | Cannot occur by accident. Loading is explicit and controlled. | Can occur whenever a lazily loaded association is accessed inside a loop. |
| Relationships | Aggregate roots only. No navigable object references across aggregate boundaries. | Full bi-directional object graph navigation across entity boundaries. |
| Query language | SQL via `@Query`. No JPQL. | JPQL via `@Query`, or native SQL with `nativeQuery = true`. |
| `save()` behaviour | Always required to persist a new or modified object. | Required for new (transient) objects. Redundant for managed objects inside a transaction. |
| Performance predictability | High. SQL is explicit and visible. No hidden queries. | Lower. Lazy loading, dirty checking, and flush ordering can produce unexpected SQL. |
| Best fit | Simple to moderate domain models, performance-sensitive code, teams that prefer explicit SQL control. | Complex object graphs, rich domain models where navigable relationships reduce boilerplate. |

The key insight to carry through this lab: Spring Data JDBC never surprises you. Every query that goes to Oracle is one you caused, either directly through a repository call or through the aggregate load. Spring Data JPA can produce database activity you did not anticipate. Both are valid choices, and knowing when to use each is the skill this week is building.

---

## The Domain

You will build a help desk ticketing API. The schema has two tables: `DEPARTMENTS` and `TICKETS`. A department owns multiple tickets. Each ticket belongs to exactly one department.

In JPA terms you would map this as two entities with a `@OneToMany` and `@ManyToOne` relationship and navigate between them freely. In Spring Data JDBC, `Department` is an aggregate root that contains a set of `Ticket` objects embedded within it. The `TicketRepository` does not exist. You access tickets only through the `DepartmentRepository`. This is the aggregate root model from Domain-Driven Design: the root controls everything inside its boundary.

---

## Before You Start

This lab uses the same Oracle instance, the same `labuser` account, and the same `XEPDB1` pluggable database as Lab 3-3. If you have already completed Lab 3-3 and can connect to your Oracle instance as labuser/labpass123.

The rest of the lab assumes you have connected to Oracle, either the installed version on your VM or the Docker version.

Once logged in:

Confirm no conflicting tables exist:

```sql
SELECT table_name FROM user_tables ORDER BY table_name;
```

If `DEPARTMENTS` or `TICKETS` already appear from a previous attempt, drop them:

```sql
DROP TABLE tickets;
DROP TABLE departments;
```

`TICKETS` must be dropped first because it holds the foreign key referencing `DEPARTMENTS`. If you drop `DEPARTMENTS` first, Oracle returns `ORA-02449: unique/primary keys in table referenced by foreign keys`. If neither table is present, the schema is clean and you are ready to proceed.

---

## Part 1 - Create the Schema in Oracle

You own the DDL. Spring Data JDBC never touches the schema.


### Step 1.1 - Create the DEPARTMENTS table

```sql
CREATE TABLE departments (
  department_id   NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  name            VARCHAR2(100) NOT NULL,
  location        VARCHAR2(100),
  created_date    DATE DEFAULT SYSDATE
);
```

> **Two important DDL decisions for Spring Data JDBC:**
>
> `GENERATED BY DEFAULT AS IDENTITY` is required on both primary key columns instead of the simpler `GENERATED AS IDENTITY`. Spring Data JDBC saves an aggregate by deleting all child rows and re-inserting them, including existing rows that already carry known primary key values. When re-inserting an existing ticket, Spring Data JDBC provides that ticket's ID explicitly in the INSERT. Plain `GENERATED AS IDENTITY` rejects explicit ID values and throws `ORA-00001`. `GENERATED BY DEFAULT AS IDENTITY` tells Oracle to accept an explicitly provided value when one is given, and to use the sequence only when no value is supplied. Both tables must use this form or saving an aggregate with existing children will fail.
>
> `created_date` is defined without `NOT NULL`. Spring Data JDBC discovers all Oracle columns through database metadata and will attempt to write a value for every column it finds, even columns with no matching Java field. A nullable `created_date` accepts the null that Spring Data JDBC writes for unmapped columns, while Oracle's `DEFAULT SYSDATE` populates the value correctly for new rows inserted without an explicit value.

### Step 1.2 - Create the TICKETS table

```sql
CREATE TABLE tickets (
  ticket_id       NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
  department_id   NUMBER        NOT NULL,
  title           VARCHAR2(200) NOT NULL,
  description     VARCHAR2(1000),
  status          VARCHAR2(20)  DEFAULT 'OPEN' NOT NULL,
  priority        VARCHAR2(10)  DEFAULT 'MEDIUM' NOT NULL,
  created_date    DATE DEFAULT SYSDATE,
  CONSTRAINT fk_ticket_dept FOREIGN KEY (department_id)
    REFERENCES departments(department_id),
  CONSTRAINT chk_status CHECK (status IN ('OPEN', 'IN_PROGRESS', 'RESOLVED', 'CLOSED')),
  CONSTRAINT chk_priority CHECK (priority IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL'))
);
```

### Step 1.3 - Insert sample data

```sql
INSERT INTO departments (name, location) VALUES ('Infrastructure', 'Floor 2');
INSERT INTO departments (name, location) VALUES ('Application Support', 'Floor 3');
INSERT INTO departments (name, location) VALUES ('Security', 'Floor 4');
COMMIT;
```

```sql
INSERT INTO tickets (department_id, title, description, status, priority) VALUES
  (1, 'Database server unresponsive',
   'Primary DB server stopped responding at 14:30. Failover did not trigger.',
   'IN_PROGRESS', 'CRITICAL');

INSERT INTO tickets (department_id, title, description, status, priority) VALUES
  (1, 'Network switch replacement required',
   'Switch on Floor 2 east wing showing intermittent packet loss.',
   'OPEN', 'HIGH');

INSERT INTO tickets (department_id, title, description, status, priority) VALUES
  (1, 'SSL certificate expiry warning',
   'Wildcard cert expires in 14 days. Renewal needed.',
   'OPEN', 'MEDIUM');

INSERT INTO tickets (department_id, title, description, status, priority) VALUES
  (2, 'Payroll application login failure',
   'Multiple users unable to authenticate since the morning deployment.',
   'IN_PROGRESS', 'CRITICAL');

INSERT INTO tickets (department_id, title, description, status, priority) VALUES
  (2, 'Report export producing blank PDFs',
   'Monthly report export returns a blank PDF for any date range over 30 days.',
   'OPEN', 'HIGH');

INSERT INTO tickets (department_id, title, description, status, priority) VALUES
  (3, 'Suspicious login attempts from unknown IP',
   'Repeated failed logins from 203.0.113.42 targeting admin accounts.',
   'IN_PROGRESS', 'CRITICAL');

INSERT INTO tickets (department_id, title, description, status, priority) VALUES
  (3, 'VPN access policy review',
   'Quarterly review of VPN group assignments due.',
   'OPEN', 'LOW');
COMMIT;
```

Verify the data:

```sql
SELECT t.title, t.status, t.priority, d.name AS department
FROM   tickets t
JOIN   departments d ON d.department_id = t.department_id
ORDER  BY d.name, t.priority DESC;
```

You should see all seven tickets with their department names.

---

## Part 2 - Create the Spring Boot Project

### Step 2.1 - Generate the project from Spring Initializr

Open [https://start.spring.io](https://start.spring.io) and configure as follows:

| Setting | Value |
|---------|-------|
| Project | Maven |
| Language | Java |
| Spring Boot | Latest stable 3.x |
| Group | `com.example` |
| Artifact | `helpdesk` |
| Packaging | Jar |
| Java | 17 |

Add the following dependencies:

- **Spring Web**
- **Spring Data JDBC**
- **Oracle Driver**
- **Spring Boot DevTools**
- **Validation**

> **JPA vs JDBC dependency:** In Lab 3.3 you selected **Spring Data JPA**, which pulled in Hibernate, the Jakarta Persistence API, and all the ORM machinery. Here you select **Spring Data JDBC**, which pulls in only Spring's `JdbcTemplate` and the Spring Data JDBC mapping layer. There is no Hibernate in this project. There is no `EntityManager`. There is no JPA spec at all. If you search the classpath, you will not find `hibernate-core`.

> **Initializr search trap:** When you type "jdbc" into the dependency search box, the results include Spring Data JDBC, Spring JDBC, and Spring Session (which has a JDBC sub-option). These look similar. Select **Spring Data JDBC** specifically. The selected chip must read exactly "Spring Data JDBC" before you click Generate.

Click **Generate**, unzip the archive, and open the project in IntelliJ via **File -> Open -> New Window**.

Wait for Maven to finish downloading dependencies before continuing.

### Step 2.2 - Verify the pom.xml has the correct dependency

Before writing any code, open `pom.xml` and confirm the Spring Data dependency reads exactly as follows:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jdbc</artifactId>
</dependency>
```

The artifactId must be `spring-boot-starter-data-jdbc`. If it reads `spring-session-jdbc` you selected Spring Session instead of Spring Data JDBC. This is are common mistakes.

If either wrong artifact is present, delete the project, return to [https://start.spring.io](https://start.spring.io), and regenerate with **Spring Data JDBC** selected. Do not attempt to fix it by editing the pom manually, as JPA and JDBC have conflicting auto-configuration that causes unpredictable startup behavior.

Also confirm that `hibernate-core` does **not** appear anywhere in `pom.xml`. If it does, the wrong starter was selected.

The complete application dependency block should look exactly like this:

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-data-jdbc</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-web</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-validation</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-devtools</artifactId>
    <scope>runtime</scope>
    <optional>true</optional>
</dependency>
<dependency>
    <groupId>com.oracle.database.jdbc</groupId>
    <artifactId>ojdbc11</artifactId>
    <scope>runtime</scope>
</dependency>
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-test</artifactId>
    <scope>test</scope>
</dependency>
```

### Step 2.3 - Configure the datasource

Rename `application.properties` to `application.yaml` using **Refactor -> Rename** in the IntelliJ Project panel.

Open `application.yaml` and add:

```yaml
spring:
  datasource:
    url: jdbc:oracle:thin:@localhost:1521/XEPDB1
    username: labuser
    password: labpass123
    driver-class-name: oracle.jdbc.OracleDriver

logging:
  level:
    org.springframework.jdbc.core: DEBUG
```

**==> Remember that if you are using Dockert, to change the url to**

`jdbc:oracle:thin:@localhost:1522/XEPDB1`

**Docker uses port 1522 instead of 1521**

> **What changed from Lab 3-3:** There is no `spring.jpa` block at all. Spring Data JDBC does not use JPA, so there is nothing to configure there. The `show-sql: true` setting from Lab 3.3 was a JPA/Hibernate setting. Here you get equivalent SQL visibility by setting the `JdbcTemplate` log level to `DEBUG`. Every SQL statement Spring Data JDBC sends to Oracle will appear in the console under the `o.s.jdbc.core` logger.

### Step 2.4 - Create the package structure

Right-click `src/main/java/com/example/helpdesk` in the Project panel and create these sub-packages:

```
com.example.helpdesk
├── config
├── controller
├── dto
├── model
├── repository
└── service
```

> **`model` instead of `entity`:** In Spring Data JDBC, the classes that map to database rows are not JPA entities. They carry no `@Entity` annotation and Hibernate never touches them. The convention in Spring Data JDBC projects is to call the package `model` rather than `entity` to make this distinction visible. The `config` package is new in this lab and will hold the Oracle identifier configuration created in Part 3.

---

## Part 3 - Configure Oracle Identifier Handling

This part must be completed before writing any model class. Skipping it causes an `ORA-00942: table or view does not exist` error at runtime.

### Step 3.1 - Understand the problem

By default, Spring Data JDBC 2.0 and later wraps all table and column names in double quotes when generating SQL. This produces statements like:

```sql
SELECT "departments"."name" FROM "departments" WHERE "departments"."department_id" = ?
```

Oracle treats double-quoted identifiers as case-sensitive. Because you created the tables in Part 1 without quotes, Oracle stored the names as `DEPARTMENTS` and `TICKETS` in uppercase. The lowercase `"departments"` that Spring Data JDBC sends does not match `DEPARTMENTS`, so Oracle returns `ORA-00942`.

The fix is to turn off forced quoting. Spring Data JDBC exposes this through a configuration bean.

### Step 3.2 - Create JdbcConfig.java

Create `JdbcConfig.java` in the `config` package:

```java
package com.example.helpdesk.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.jdbc.core.convert.JdbcCustomConversions;
import org.springframework.data.jdbc.core.mapping.JdbcMappingContext;
import org.springframework.data.jdbc.repository.config.AbstractJdbcConfiguration;
import org.springframework.data.relational.RelationalManagedTypes;
import org.springframework.data.relational.core.mapping.NamingStrategy;

import java.util.Optional;

@Configuration
public class JdbcConfig extends AbstractJdbcConfiguration {

    @Bean
    @Override
    public JdbcMappingContext jdbcMappingContext(
            Optional<NamingStrategy> namingStrategy,
            JdbcCustomConversions customConversions,
            RelationalManagedTypes jdbcManagedTypes) {

        JdbcMappingContext context =
                super.jdbcMappingContext(namingStrategy, customConversions, jdbcManagedTypes);
        context.setForceQuote(false);
        return context;
    }
}
```

**What this does:** `setForceQuote(false)` tells Spring Data JDBC to send table and column names to Oracle without wrapping them in double quotes. Oracle receives unquoted identifiers, folds them to uppercase internally, and matches them against `DEPARTMENTS` and `TICKETS` correctly.

**Import to watch for:** `RelationalManagedTypes` must be imported from `org.springframework.data.relational.RelationalManagedTypes`. IntelliJ may suggest `org.springframework.data.relational.core.mapping.RelationalManagedTypes`, which does not exist. If IntelliJ cannot resolve the symbol at all, check that `spring-boot-starter-data-jdbc` is present in `pom.xml`.

**Why this is not needed in Lab 3.3:** JPA/Hibernate manages its own SQL generation and dialect handling independently of Spring Data JDBC. The quoting behaviour described here is specific to Spring Data JDBC.

---

## Part 4 - Map the Aggregate

This is the most important part of the lab conceptually. Read every comment in the code before moving on.

### Spring Data JDBC annotation imports - read before writing any model class

Every annotation used in the model classes comes from Spring Data packages, not from JPA. IntelliJ will show a red underline if the wrong package is imported. Use this table as a reference whenever IntelliJ cannot resolve an annotation symbol.

| Annotation | Correct import | Wrong import to avoid |
|------------|---------------|----------------------|
| `@Id` | `org.springframework.data.annotation.Id` | `jakarta.persistence.Id` (JPA) |
| `@Table` | `org.springframework.data.relational.core.mapping.Table` | `jakarta.persistence.Table` (JPA) |
| `@Column` | `org.springframework.data.relational.core.mapping.Column` | `jakarta.persistence.Column` (JPA) |
| `@MappedCollection` | `org.springframework.data.relational.core.mapping.MappedCollection` | does not exist in JPA |

If any of these packages cannot be found by IntelliJ even after a Maven reload, it means `spring-boot-starter-data-jdbc` is not in your `pom.xml`. Return to Step 2.2 and verify the dependency before continuing.

> **Why the same annotation names exist in two packages:** Both Spring Data JDBC and JPA define annotations called `@Id`, `@Table`, and `@Column`, but they are completely different types processed by different frameworks. Importing the JPA version into a Spring Data JDBC class compiles without error but the class will not be mapped correctly at runtime, producing confusing `BadSqlGrammarException` failures. Always verify the import source when an annotation appears to be ignored.

### Step 4.1 - Understand the aggregate model before writing any code

In Lab 3.3 (JPA), you mapped two independent entity classes: `Category` and `Product`. Each had its own repository. You could load a `Product` without loading its `Category`, and vice versa. JPA navigated between them through object references and lazy loading.

Spring Data JDBC does not work this way. It uses the **aggregate root** pattern. An aggregate is a cluster of objects that always travel together: they are loaded together, saved together, and deleted together. The aggregate root is the top-level class. It is the only class that has a repository. Child objects inside the aggregate are not independently accessible.

In this lab:

- `Department` is the aggregate root. It has a repository.
- `Ticket` is a child object inside the `Department` aggregate. It does not have its own repository.
- To find a ticket, you load the department that owns it and look through its ticket set.
- To save a new ticket, you add it to the department's ticket set and save the department.

This feels constraining at first, but it enforces a discipline that prevents accidental cross-boundary access and makes the data model's boundaries explicit in the Java code.

### Step 4.2 - Understand how Spring Data JDBC handles Oracle default columns

Spring Data JDBC discovers columns by reading Oracle database metadata at startup, not only by reading the Java class fields. This means it is aware of the `created_date` column on both tables even if no Java field maps to it. When Spring Data JDBC generates an INSERT, it includes every column it knows about from metadata. If no Java field provides a value, it writes null for that column.

This creates a problem with columns that have Oracle `DEFAULT` values and a `NOT NULL` constraint. Oracle applies the default only when the column is completely absent from the INSERT. When Spring Data JDBC includes the column with a null value, Oracle receives an explicit null and rejects it with `ORA-01400`, ignoring the default entirely.

The DDL in this lab addresses this in two ways. First, `created_date` is defined without `NOT NULL`, so Oracle accepts the null that Spring Data JDBC writes for that column. Second, the `DEFAULT SYSDATE` still fires for rows inserted from SQL*Plus without an explicit `created_date` value, so the sample data rows have correct dates.

In the Java model classes, `created_date` is annotated with `@ReadOnlyProperty` from `org.springframework.data.annotation.ReadOnlyProperty`. This annotation tells Spring Data JDBC to read the column value on SELECT but never include it in INSERT or UPDATE statements. Combined with the nullable DDL, this gives the correct behaviour: Oracle manages the date, Java can read it back, and Spring Data JDBC never tries to write it.

This is different from JPA, where `@Column(insertable = false, updatable = false)` achieves a similar result through the Hibernate layer rather than through the Spring Data JDBC mapping layer.

### Step 4.3 - Create the Ticket model class

Create `Ticket.java` in the `model` package:

```java
package com.example.helpdesk.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.ReadOnlyProperty;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.Table;

import java.time.LocalDate;

// No @Entity annotation. No Hibernate. This is a plain Java class.
// Spring Data JDBC uses its own mapping layer, configured in JdbcConfig.
@Table("tickets")
public class Ticket {

    // TODO 1: Add @Id to this field.
    // In Spring Data JDBC, @Id is from org.springframework.data.annotation.Id,
    // NOT from jakarta.persistence.Id. Make sure your import statement is correct.
    // Using the wrong @Id annotation is the single most common mistake in this lab.
    @Id
    @Column("ticket_id")
    private Long ticketId;

    // Note: there is no @ManyToOne here and no 'department' field.
    // Spring Data JDBC does not support navigable object references across aggregate boundaries.
    // The department_id foreign key is managed by the framework automatically.
    // You reference departments by ID, not by object.

    @Column("title")
    private String title;

    @Column("description")
    private String description;

    @Column("status")
    private String status;

    @Column("priority")
    private String priority;

    // @ReadOnlyProperty tells Spring Data JDBC to read this column on SELECT
    // but never include it in INSERT or UPDATE statements.
    // Oracle's DEFAULT SYSDATE then populates the value automatically on insert.
    // Import: org.springframework.data.annotation.ReadOnlyProperty
    // NOT jakarta.persistence.Column (which has insertable = false).
    @ReadOnlyProperty
    @Column("created_date")
    private LocalDate createdDate;

    // Spring Data JDBC requires a default constructor
    public Ticket() {}

    public Ticket(String title, String description, String status, String priority) {
        this.title = title;
        this.description = description;
        this.status = status;
        this.priority = priority;
    }

    public Long getTicketId() { return ticketId; }
    public void setTicketId(Long ticketId) { this.ticketId = ticketId; }

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }

    public String getPriority() { return priority; }
    public void setPriority(String priority) { this.priority = priority; }

    public LocalDate getCreatedDate() { return createdDate; }
}
```

### Step 4.4 - Create the Department aggregate root

Create `Department.java` in the `model` package:

```java
package com.example.helpdesk.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.annotation.ReadOnlyProperty;
import org.springframework.data.relational.core.mapping.Column;
import org.springframework.data.relational.core.mapping.MappedCollection;
import org.springframework.data.relational.core.mapping.Table;

import java.time.LocalDate;
import java.util.HashSet;
import java.util.Set;

@Table("departments")
public class Department {

    @Id
    @Column("department_id")
    private Long departmentId;

    @Column("name")
    private String name;

    @Column("location")
    private String location;

    // @ReadOnlyProperty tells Spring Data JDBC to read this column on SELECT
    // but never include it in INSERT or UPDATE statements.
    // Oracle's DEFAULT SYSDATE populates the value automatically on insert.
    @ReadOnlyProperty
    @Column("created_date")
    private LocalDate createdDate;

    // TODO 2: Add the @MappedCollection annotation to the tickets field.
    //
    // @MappedCollection tells Spring Data JDBC that this Set<Ticket> maps to rows
    // in the TICKETS table. The idColumn attribute names the foreign key column
    // in the TICKETS table that references this aggregate root.
    //
    // Use: @MappedCollection(idColumn = "department_id")
    //
    // Compare this to JPA's @OneToMany(mappedBy = "department", fetch = FetchType.LAZY).
    // The critical differences:
    //   - There is no mappedBy because Ticket has no 'department' field to map by.
    //   - There is no FetchType parameter because there is no lazy loading.
    //     When you load a Department, its tickets are ALWAYS loaded. Always.
    //   - Spring Data JDBC uses a Set rather than a List by convention.
    @MappedCollection(idColumn = "department_id")
    private Set<Ticket> tickets = new HashSet<>();

    public Department() {}

    public Department(String name, String location) {
        this.name = name;
        this.location = location;
    }

    // Convenience method to add a ticket to this aggregate.
    // Because Ticket has no reference back to its department,
    // you add tickets by calling this method and then saving the Department.
    public void addTicket(Ticket ticket) {
        this.tickets.add(ticket);
    }

    public Long getDepartmentId() { return departmentId; }
    public void setDepartmentId(Long departmentId) { this.departmentId = departmentId; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }

    public LocalDate getCreatedDate() { return createdDate; }

    public Set<Ticket> getTickets() { return tickets; }
    public void setTickets(Set<Ticket> tickets) { this.tickets = tickets; }
}
```

### Step 4.4 - Start the application and observe the startup log

Run `HelpdeskApplication.java`. You should see output similar to this:

```
Bootstrapping Spring Data JDBC repositories in DEFAULT mode.
Finished Spring Data JDBC repository scanning in X ms. Found 0 JDBC repository interfaces.
```

It found zero repositories because you have not created one yet. That is expected at this stage. What you should NOT see is any Hibernate output, any JPA schema validation, or any `HHH` prefixed messages. Spring Data JDBC does not use Hibernate. If you see Hibernate messages, check your `pom.xml` and confirm you added **Spring Data JDBC**, not Spring Data JPA.

---

## Part 5 - Declare the Repository

### Step 5.1 - Create DepartmentRepository

Create `DepartmentRepository.java` in the `repository` package:

```java
package com.example.helpdesk.repository;

import com.example.helpdesk.model.Department;
import org.springframework.data.jdbc.repository.query.Query;
import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface DepartmentRepository extends CrudRepository<Department, Long> {

    // TODO 3: Add a derived query method that finds a Department by its name field.
    // The method signature is: Optional<Department> findByName(String name);
    // Spring Data JDBC supports the same method name derivation grammar as Spring Data JPA.
    // The generated query will be SQL, not JPQL: WHERE name = :name
    Optional<Department> findByName(String name);

    // TODO 4: Add a native SQL query that returns all departments ordered by name.
    // In Spring Data JDBC, @Query always means native SQL. There is no JPQL.
    // Use: @Query("SELECT * FROM departments ORDER BY name ASC")
    //
    // The correct import for @Query is:
    //   org.springframework.data.jdbc.repository.query.Query
    //
    // NOT org.springframework.data.jpa.repository.Query (the JPA version).
    // IntelliJ may offer both as autocomplete options. Select the jdbc one.
    // The JPA version compiles without error but is silently ignored at runtime.
    @Query("SELECT * FROM departments ORDER BY name ASC")
    List<Department> findAllOrderedByName();
}
```

> **No TicketRepository:** There is no `TicketRepository`. In Spring Data JDBC you do not create repositories for child objects inside an aggregate. Tickets are accessed and modified exclusively through `DepartmentRepository`. If you created a `TicketRepository`, Spring Data JDBC would treat `Ticket` as its own aggregate root and the parent-child relationship would break.

### Step 5.2 - Restart and verify repository scanning

Run `HelpdeskApplication.java` again. The log should now show:

```
Finished Spring Data JDBC repository scanning in X ms. Found 1 JDBC repository interface.
```

One repository. Not two. If you see two, you have accidentally created a `TicketRepository`. Delete it before continuing.

---

## Part 6 - Understand Aggregate Loading

This is the most important observation in the lab. Complete it before writing the service layer.

### Step 6.1 - Add a temporary inspection block to observe loading

Add the following temporary `@PostConstruct` method to `HelpdeskApplication.java`:

```java
package com.example.helpdesk;

import com.example.helpdesk.repository.DepartmentRepository;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class HelpdeskApplication {

    @Autowired
    private DepartmentRepository departmentRepository;

    public static void main(String[] args) {
        SpringApplication.run(HelpdeskApplication.class, args);
    }

    @PostConstruct
    public void inspect() {
        System.out.println("=== Loading department with ID 1 ===");
        departmentRepository.findById(1L).ifPresent(dept -> {
            System.out.println("Department: " + dept.getName());
            System.out.println("Ticket count: " + dept.getTickets().size());
            dept.getTickets().forEach(t ->
                System.out.println("  Ticket: " + t.getTitle() + " [" + t.getStatus() + "]")
            );
        });
    }
}
```

Run the application and watch the IntelliJ console carefully. You will see two SQL statements in the `DEBUG` output from `o.s.jdbc.core`:

```
Executing prepared SQL query
Executing SQL statement [SELECT ... FROM departments WHERE department_id = ?]

Executing prepared SQL query
Executing SQL statement [SELECT ... FROM tickets WHERE tickets.department_id = ?]
```

**Two queries. Always two queries. Never more, never fewer.**

Spring Data JDBC loaded the `Department` row with the first query and then immediately loaded all its `Ticket` rows with the second query. It did not wait for you to call `getTickets()`. There is no proxy. There is no lazy trigger. The tickets were already in memory by the time your `println` ran.

If you still see `ORA-00942` at this point, the `JdbcConfig` class from Part 3 is not being picked up. Confirm the class is in the `com.example.helpdesk.config` package, that it is annotated with `@Configuration`, and that `RelationalManagedTypes` is imported from `org.springframework.data.relational.RelationalManagedTypes`.

### Step 6.2 - Compare this to Lab 3.3 JPA behaviour

In Lab 3.3, loading a `Category` without `JOIN FETCH` produced one query for the category and then one additional query per product the first time you accessed each product's data. That was the N+1 problem. With `JOIN FETCH`, it became one query.

In this lab, loading a `Department` always produces exactly two queries regardless of what you do with the tickets afterward. You cannot produce an N+1 problem by accident because there is no lazy loading to accidentally trigger.

The tradeoff is that you always pay the cost of loading all tickets for a department even when you only need the department's name. In JPA you could load the category without its products. In Spring Data JDBC you cannot load a department without its tickets. This is why aggregate design matters: you must think carefully about what belongs inside an aggregate boundary and what belongs outside it.

### Step 6.3 - Remove the @PostConstruct method

Delete the `inspect()` method and the `@Autowired` field from `HelpdeskApplication.java` before continuing. The class should return to its generated state with only `main()`.

---

## Part 7 - Define the DTOs

Create `DepartmentDto.java` in the `dto` package:

```java
package com.example.helpdesk.dto;

import java.util.List;

public class DepartmentDto {

    private Long departmentId;
    private String name;
    private String location;
    private List<TicketDto> tickets;

    public DepartmentDto(Long departmentId, String name,
                         String location, List<TicketDto> tickets) {
        this.departmentId = departmentId;
        this.name = name;
        this.location = location;
        this.tickets = tickets;
    }

    public Long getDepartmentId() { return departmentId; }
    public String getName() { return name; }
    public String getLocation() { return location; }
    public List<TicketDto> getTickets() { return tickets; }
}
```

Create `TicketDto.java` in the `dto` package:

```java
package com.example.helpdesk.dto;

public class TicketDto {

    private Long ticketId;
    private String title;
    private String description;
    private String status;
    private String priority;

    public TicketDto(Long ticketId, String title, String description,
                     String status, String priority) {
        this.ticketId = ticketId;
        this.title = title;
        this.description = description;
        this.status = status;
        this.priority = priority;
    }

    public Long getTicketId() { return ticketId; }
    public String getTitle() { return title; }
    public String getDescription() { return description; }
    public String getStatus() { return status; }
    public String getPriority() { return priority; }
}
```

Create `TicketCreateRequest.java` in the `dto` package:

```java
package com.example.helpdesk.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public class TicketCreateRequest {

    @NotBlank
    @Size(max = 200)
    private String title;

    @Size(max = 1000)
    private String description;

    @NotBlank
    @Pattern(regexp = "LOW|MEDIUM|HIGH|CRITICAL",
             message = "Priority must be LOW, MEDIUM, HIGH, or CRITICAL")
    private String priority;

    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public String getPriority() { return priority; }
    public void setPriority(String priority) { this.priority = priority; }
}
```

---

## Part 8 - Implement the Service Layer

Create `DepartmentService.java` in the `service` package:

```java
package com.example.helpdesk.service;

import com.example.helpdesk.dto.DepartmentDto;
import com.example.helpdesk.dto.TicketCreateRequest;
import com.example.helpdesk.dto.TicketDto;
import com.example.helpdesk.model.Department;
import com.example.helpdesk.model.Ticket;
import com.example.helpdesk.repository.DepartmentRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
public class DepartmentService {

    private final DepartmentRepository departmentRepository;

    public DepartmentService(DepartmentRepository departmentRepository) {
        this.departmentRepository = departmentRepository;
    }

    @Transactional(readOnly = true)
    public List<DepartmentDto> findAll() {
        // TODO 5: Call departmentRepository.findAllOrderedByName(),
        // map each Department to a DepartmentDto using toDepartmentDto(),
        // and return the list.
        //
        // Note: Spring Data JDBC will execute one SELECT on DEPARTMENTS and then
        // one SELECT on TICKETS per department row returned. With 3 departments
        // this produces 4 queries total (1 + 3). Check the console log after
        // you implement and call this endpoint. Count the queries.
        //
        // This is not N+1 in the JPA sense. It is the defined aggregate loading
        // behaviour of Spring Data JDBC. You cannot avoid it for findAll().
        // If you need a different shape, write a custom @Query.
        List<Department> departments = departmentRepository.findAllOrderedByName();
        return departments.stream()
                .map(this::toDepartmentDto)
                .toList();
    }

    @Transactional(readOnly = true)
    public DepartmentDto findById(Long id) {
        // TODO 6: Use departmentRepository.findById(id).
        // Throw NoSuchElementException("Department not found: " + id) if absent.
        // Map and return the DepartmentDto.
        return departmentRepository.findById(id)
                .map(this::toDepartmentDto)
                .orElseThrow(() -> new NoSuchElementException("Department not found: " + id));
    }

    @Transactional
    public DepartmentDto addTicket(Long departmentId, TicketCreateRequest request) {
        // TODO 7: Load the department. Throw NoSuchElementException if not found.
        //
        // Construct a new Ticket from the request fields.
        // Set status to "OPEN" -- new tickets always start open.
        //
        // Call department.addTicket(ticket).
        //
        // Call departmentRepository.save(department).
        //
        // IMPORTANT: In Spring Data JDBC, save() on the aggregate root is always
        // required to persist a change. There is no dirty checking. If you modify
        // the department or add a ticket but do not call save(), nothing happens
        // to the database. This is the opposite of what you saw in Lab 3.3's
        // adjustStock() method, where Hibernate's dirty checking issued the UPDATE
        // without an explicit save() call.
        //
        // Return the updated DepartmentDto.
        Department department = departmentRepository.findById(departmentId)
                .orElseThrow(() -> new NoSuchElementException("Department not found: " + departmentId));

        Ticket ticket = new Ticket(
                request.getTitle(),
                request.getDescription(),
                "OPEN",
                request.getPriority()
        );
        department.addTicket(ticket);

        Department saved = departmentRepository.save(department);
        return toDepartmentDto(saved);
    }

    @Transactional
    public DepartmentDto resolveTicket(Long departmentId, Long ticketId) {
        // TODO 8: Load the department. Throw NoSuchElementException if not found.
        //
        // Find the ticket in department.getTickets() whose ticketId matches.
        // Throw NoSuchElementException("Ticket not found: " + ticketId) if not found.
        //
        // Call ticket.setStatus("RESOLVED").
        //
        // Call departmentRepository.save(department).
        //
        // This is where the no-dirty-checking rule becomes concrete. You modified
        // the ticket's status field. In JPA, inside a @Transactional method,
        // that change would be detected automatically and an UPDATE would fire.
        // In Spring Data JDBC, calling setStatus() on the Ticket does nothing to
        // the database until you call save() on the owning Department aggregate root.
        // If you forget save(), you return a DTO with status = RESOLVED but Oracle
        // still has status = IN_PROGRESS. Run the endpoint without save() first
        // (Step 10.6), then add it back and compare the console output.
        Department department = departmentRepository.findById(departmentId)
                .orElseThrow(() -> new NoSuchElementException("Department not found: " + departmentId));

        Ticket ticket = department.getTickets().stream()
                .filter(t -> t.getTicketId().equals(ticketId))
                .findFirst()
                .orElseThrow(() -> new NoSuchElementException("Ticket not found: " + ticketId));

        ticket.setStatus("RESOLVED");

        Department saved = departmentRepository.save(department);
        return toDepartmentDto(saved);
    }

    @Transactional
    public DepartmentDto createDepartment(String name, String location) {
        // TODO 9: Check for a duplicate department name using findByName(name).
        // Throw IllegalArgumentException("Department already exists: " + name) if found.
        // Construct a new Department, call departmentRepository.save(), return the DTO.
        departmentRepository.findByName(name).ifPresent(existing -> {
            throw new IllegalArgumentException("Department already exists: " + name);
        });

        Department department = new Department(name, location);
        Department saved = departmentRepository.save(department);
        return toDepartmentDto(saved);
    }

    // Mapping helpers

    private DepartmentDto toDepartmentDto(Department department) {
        List<TicketDto> ticketDtos = department.getTickets().stream()
                .map(this::toTicketDto)
                .toList();
        return new DepartmentDto(
                department.getDepartmentId(),
                department.getName(),
                department.getLocation(),
                ticketDtos
        );
    }

    private TicketDto toTicketDto(Ticket ticket) {
        return new TicketDto(
                ticket.getTicketId(),
                ticket.getTitle(),
                ticket.getDescription(),
                ticket.getStatus(),
                ticket.getPriority()
        );
    }
}
```

> **No LazyInitializationException risk:** Notice that `toDepartmentDto()` accesses `department.getTickets()` freely. There is no session to be closed, no proxy to initialize, and no risk of a `LazyInitializationException`. The tickets were loaded when the department was loaded. Calling `getTickets()` from anywhere in the codebase, including from the controller, is completely safe. This is a direct consequence of having no lazy loading.

---

## Part 9 - Implement the Controller

Create `DepartmentController.java` in the `controller` package:

```java
package com.example.helpdesk.controller;

import com.example.helpdesk.dto.DepartmentDto;
import com.example.helpdesk.dto.TicketCreateRequest;
import com.example.helpdesk.service.DepartmentService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/v1/departments")
public class DepartmentController {

    private final DepartmentService departmentService;

    public DepartmentController(DepartmentService departmentService) {
        this.departmentService = departmentService;
    }

    @GetMapping
    public List<DepartmentDto> getAll() {
        return departmentService.findAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity<DepartmentDto> getById(@PathVariable Long id) {
        try {
            return ResponseEntity.ok(departmentService.findById(id));
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }

    @PostMapping
    public ResponseEntity<DepartmentDto> create(@RequestBody Map<String, String> body) {
        try {
            String name = body.get("name");
            String location = body.get("location");
            DepartmentDto created = departmentService.createDepartment(name, location);
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().build();
        }
    }

    // TODO 10: Implement POST /api/v1/departments/{id}/tickets.
    // Accept a @Valid @RequestBody TicketCreateRequest.
    // Call departmentService.addTicket(id, request).
    // Return 201 CREATED with the updated DepartmentDto as the body.
    // Return 404 if the department is not found.
    @PostMapping("/{id}/tickets")
    public ResponseEntity<DepartmentDto> addTicket(
            @PathVariable Long id,
            @Valid @RequestBody TicketCreateRequest request) {
        try {
            DepartmentDto updated = departmentService.addTicket(id, request);
            return ResponseEntity.status(HttpStatus.CREATED).body(updated);
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }

    // TODO 11: Implement PATCH /api/v1/departments/{departmentId}/tickets/{ticketId}/resolve.
    // No request body is needed. Call departmentService.resolveTicket(departmentId, ticketId).
    // Return 200 OK with the updated DepartmentDto.
    // Return 404 if either the department or the ticket is not found.
    @PatchMapping("/{departmentId}/tickets/{ticketId}/resolve")
    public ResponseEntity<DepartmentDto> resolveTicket(
            @PathVariable Long departmentId,
            @PathVariable Long ticketId) {
        try {
            return ResponseEntity.ok(departmentService.resolveTicket(departmentId, ticketId));
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }
}
```

---

## Part 10 - Test the Application

### Step 10.1 - Start the application

Run `HelpdeskApplication.java`. The startup log should include:

```
Found 1 JDBC repository interface.
Tomcat started on port 8080 (http)
```

There will be no schema validation output because Spring Data JDBC does not validate the schema at startup. If your column names in `@Column` annotations do not match the Oracle columns, you will get a runtime error on the first query, not a startup error. This is different from Lab 3.3's `ddl-auto: validate` behaviour.

### Step 10.2 - Create the HTTP test file

Create `helpdesk-tests.http` in the project root:

```http
### List all departments (ordered by name)
GET http://localhost:8080/api/v1/departments

###

### Get a single department with all its tickets
GET http://localhost:8080/api/v1/departments/1

###

### Get a department that does not exist
GET http://localhost:8080/api/v1/departments/999

###

### Create a new department
POST http://localhost:8080/api/v1/departments
Content-Type: application/json

{
  "name": "Database Administration",
  "location": "Floor 5"
}

###

### Attempt to create a duplicate department - should return 400
POST http://localhost:8080/api/v1/departments
Content-Type: application/json

{
  "name": "Security",
  "location": "Floor 1"
}

###

### Add a ticket to a department
POST http://localhost:8080/api/v1/departments/1/tickets
Content-Type: application/json

{
  "title": "Disk space alert on backup server",
  "description": "Backup drive at 94% capacity. Archiving required.",
  "priority": "HIGH"
}

###

### Resolve a ticket (replace 1 with actual ticket IDs from previous responses)
PATCH http://localhost:8080/api/v1/departments/1/tickets/1/resolve

###

### Invalid priority - should return 400 from Bean Validation
POST http://localhost:8080/api/v1/departments/1/tickets
Content-Type: application/json

{
  "title": "Test ticket",
  "description": "Invalid priority value",
  "priority": "URGENT"
}
```

### Step 10.3 - Run the list endpoint and count the queries

Execute **List all departments**. In the console you will see SQL output from the `o.s.jdbc.core` logger. Count the statements:

- 1 SELECT on `DEPARTMENTS` (returning 3 rows)
- 3 SELECT statements on `TICKETS` (one per department)

Total: 4 queries for 3 departments. With 10 departments it would be 11 queries. This is the aggregate loading behaviour of Spring Data JDBC. It is predictable, visible, and consistent. It is not a bug. It is the defined cost of the aggregate root pattern.

### Step 10.4 - Run the get single department endpoint

Execute **Get a single department with all its tickets**. You will see exactly 2 queries in the console: one for the department row and one for all its tickets. Regardless of how many tickets that department has, it is always 2 queries.

### Step 10.5 - Add a ticket and observe the save behaviour

Execute **Add a ticket to a department**. Watch the console output. You will see:

1. A SELECT to load the department and its existing tickets
2. An INSERT for the new ticket row
3. UPDATE statements on the existing ticket rows in the department

> **Why the UPDATEs on existing tickets?** When you call `departmentRepository.save(department)`, Spring Data JDBC saves the entire aggregate. Its strategy is to write the entire child set, not just the modified or new rows. This is a known characteristic of Spring Data JDBC and is one of the reasons you think carefully about what belongs inside an aggregate. Aggregates with many child objects can produce significant write traffic on save. For large child sets, a custom `@Query` with an explicit INSERT is more appropriate.

### Step 10.6 - Resolve a ticket and observe the missing save effect

Before running the resolve endpoint, temporarily comment out the `departmentRepository.save(saved)` call in `resolveTicket()` in the service. Replace the return statement with `return toDepartmentDto(department)`.

Run the **Resolve a ticket** endpoint. The response JSON will show `"status": "RESOLVED"`. Now run **Get a single department** to reload the same department from Oracle. The ticket will still show its original status. The in-memory change was returned in the response but was never persisted because `save()` was not called.

Restore `departmentRepository.save(saved)` and run the resolve endpoint again. This time the reload will show `"status": "RESOLVED"` in Oracle.

This is the most important hands-on demonstration of the difference between Spring Data JDBC and Lab 3.3. In Lab 3.3's `adjustStock()`, you saw that Hibernate persisted the change even without `save()`. Here you can see with your own eyes that without `save()`, the change is lost.

---

## Part 11 - Side-by-Side Comparison

Work through this section after completing all the test steps. It maps every key observation from both labs to a concrete explanation.

### Observation 1 - What the startup log tells you

| Lab 3.3 JPA | Lab 3.4 JDBC |
|-------------|--------------|
| `SchemaValidator - Validated schema for table [categories]` | No schema validation. First query failure reveals mapping errors. |
| `Found 2 JPA repository interfaces.` | `Found 1 JDBC repository interface.` |
| Hibernate version and configuration messages | No Hibernate messages at all. |
| No Oracle quoting configuration required | Requires `JdbcConfig` with `setForceQuote(false)` to work with Oracle. |

### Observation 2 - What loading an object produces

| Scenario | Lab 3.3 JPA | Lab 3.4 JDBC |
|----------|-------------|--------------|
| Load a single parent (Category / Department) | 1 query. Child list is not loaded. | 2 queries. Child set is always loaded. |
| Access children after loading | Triggers lazy SELECT per child if not JOIN FETCHed. | No query. Already in memory. |
| Load a list of 3 parents | 1 query (just parents). | 4 queries (1 parent + 3 child sets). |
| Can N+1 occur accidentally? | Yes. Accessing lazy association in a loop. | No. Aggregate is always fully loaded. |

### Observation 3 - What saving produces

| Scenario | Lab 3.3 JPA | Lab 3.4 JDBC |
|----------|-------------|--------------|
| Load entity, change a field, do not call save() | Hibernate dirty checking issues UPDATE at transaction commit. | Nothing happens. Oracle is unchanged. |
| Load entity, change a field, call save() | Harmless but redundant for managed entities. | Required. This is how the change reaches Oracle. |
| Add a new child object and save parent | JPA cascades if configured with CascadeType. | Spring Data JDBC saves the entire child set. |

### Observation 4 - Query language

| Lab 3.3 JPA | Lab 3.4 JDBC |
|-------------|--------------|
| `@Query("SELECT p FROM Product p WHERE ...")` is JPQL, uses Java field names. | `@Query("SELECT * FROM tickets WHERE ...")` is always native SQL. |
| `@Query(value = "...", nativeQuery = true)` for Oracle-specific SQL. | No `nativeQuery` attribute needed. All queries are native. |
| `JOIN FETCH` in JPQL to prevent N+1. | No JOIN FETCH needed. No lazy loading to prevent. |

---


## Lab Summary

In this lab you:

- Built a Spring Boot application using Spring Data JDBC, with no Hibernate and no JPA on the classpath
- Created a `JdbcConfig` class to disable forced identifier quoting, which is required for Spring Data JDBC to work correctly with Oracle
- Learned that Oracle columns with `DEFAULT` values must not be mapped in the Java model class, because Spring Data JDBC includes every mapped field in INSERT statements, causing `ORA-01400` when the Java value is null
- Modelled a `Department` aggregate root containing a `Set<Ticket>`, and saw that `Ticket` has no repository of its own
- Observed that loading a `Department` always loads its `Ticket` set immediately, with no lazy loading and no proxy objects
- Confirmed that changes to in-memory objects have no effect on Oracle unless `save()` is called on the aggregate root, which is the direct opposite of JPA's dirty checking behaviour
- Traced the SQL produced by aggregate load, aggregate save, and custom `@Query` operations through the console log
- Compared every significant behaviour side by side with Lab 3.3 to understand when each approach is the right choice

---

*End of Lab 3.4*
