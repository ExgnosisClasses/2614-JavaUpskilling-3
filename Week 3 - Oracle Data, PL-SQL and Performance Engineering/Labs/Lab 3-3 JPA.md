# Lab 3-3: Spring Data JPA with Oracle

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**
**Module 5 | Estimated time: 90-120 minutes | Tools: IntelliJ IDEA Ultimate, Oracle 21c XE**

---

## Overview

This lab walks you through building a Spring Boot application with a full MVC stack backed by Spring Data JPA and an Oracle database. You will map Java entity classes to Oracle tables, declare repository interfaces, wire them into a service layer, and expose the data through a REST controller. Along the way you will observe the JPA entity lifecycle in practice and learn where the framework helps you and where it can surprise you.

By the end of this lab you will have:

- Created a Spring Boot project with JPA, Oracle JDBC, and Web dependencies
- Mapped two related Oracle tables to Java entity classes using JPA annotations
- Declared a repository interface and seen Spring Data generate the implementation at startup
- Written service methods with correct transaction boundaries
- Exposed CRUD endpoints through a REST controller
- Observed lazy loading, dirty checking, and the N+1 query problem directly in the IntelliJ console log

---

## Background - What JPA Does and Does Not Do

Spring Data JPA sits on top of the Java Persistence API, which is implemented by Hibernate. When you annotate a class with `@Entity` and a field with `@Id`, you are telling Hibernate how to map that Java object to a database row. Hibernate then manages the lifecycle of that object inside a session: it knows when you read it, when you change it, and when to flush those changes to Oracle.

Hibernate generates SQL on your behalf, and that SQL is not always what you would write by hand. Two behaviours in particular deserve attention before you start:

**Dirty checking** means Hibernate compares the state of every managed entity to its snapshot at load time when the transaction commits. If anything changed, it issues an UPDATE automatically. You do not need to call `save()` for an entity you loaded within the same transaction. Calling `save()` on an already-managed entity is harmless but redundant.

**Lazy loading** means Hibernate does not fetch a related entity from the database until your code actually accesses it. This is efficient when you do not need the related data, but it fires an additional SQL statement every time you do. If you load a list of 50 products and then access each product's category in a loop, you produce 51 queries. This is the N+1 problem. You will observe it in this lab and then fix it.

---

## The Domain

You will build a simple product catalog API for a fictional retail company. The schema has two tables: `CATEGORIES` and `PRODUCTS`. A category has many products. A product belongs to exactly one category.

This is a realistic, representative domain. It is small enough to understand immediately and rich enough to demonstrate the important JPA behaviours: a parent-child relationship, lazy loading across the association, and a query that crosses both tables.

---

## Before You Start

Make sure you have gone through the `Lab 3-3 Before You Start.md `

---


## Part 1 - Create the Schema in Oracle

You will create the two tables manually before wiring Spring Data JPA. This is the recommended approach in a professional environment: own your DDL, do not let Hibernate generate it in production.

### Step 1.1 - Connect as labuser

You should already be connected

### Step 1.2 - Create the CATEGORIES table

```sql
CREATE TABLE categories (
  category_id   NUMBER GENERATED AS IDENTITY PRIMARY KEY,
  name          VARCHAR2(100) NOT NULL,
  description   VARCHAR2(500),
  created_date  DATE DEFAULT SYSDATE NOT NULL
);
```

### Step 1.3 - Create the PRODUCTS table

```sql
CREATE TABLE products (
  product_id    NUMBER GENERATED AS IDENTITY PRIMARY KEY,
  category_id   NUMBER        NOT NULL,
  name          VARCHAR2(200) NOT NULL,
  sku           VARCHAR2(50)  UNIQUE NOT NULL,
  price         NUMBER(10,2)  NOT NULL,
  stock_qty     NUMBER        DEFAULT 0 NOT NULL,
  active        NUMBER(1)     DEFAULT 1 NOT NULL,
  CONSTRAINT fk_prod_cat FOREIGN KEY (category_id)
    REFERENCES categories(category_id)
);
```

### Step 1.4 - Insert sample data

```sql
INSERT INTO categories (name, description) VALUES
  ('Electronics', 'Consumer electronics and accessories');
INSERT INTO categories (name, description) VALUES
  ('Office Supplies', 'Stationery, paper, and desk accessories');
INSERT INTO categories (name, description) VALUES
  ('Books', 'Technical and professional books');
COMMIT;
```

```sql
INSERT INTO products (category_id, name, sku, price, stock_qty) VALUES
  (1, 'Wireless Keyboard', 'KBD-WL-001', 49.99, 120);
INSERT INTO products (category_id, name, sku, price, stock_qty) VALUES
  (1, 'USB-C Hub 7-Port', 'HUB-7C-002', 34.99, 85);
INSERT INTO products (category_id, name, sku, price, stock_qty) VALUES
  (1, 'Monitor 27 Inch', 'MON-27-003', 349.99, 22);
INSERT INTO products (category_id, name, sku, price, stock_qty) VALUES
  (2, 'Ballpoint Pens 12-Pack', 'PEN-BP-004', 6.99, 500);
INSERT INTO products (category_id, name, sku, price, stock_qty) VALUES
  (2, 'Legal Pads 6-Pack', 'PAD-LG-005', 12.49, 300);
INSERT INTO products (category_id, name, sku, price, stock_qty) VALUES
  (3, 'Clean Code', 'BK-CC-006', 39.99, 45);
INSERT INTO products (category_id, name, sku, price, stock_qty) VALUES
  (3, 'Designing Data-Intensive Applications', 'BK-DD-007', 54.99, 30);
COMMIT;
```

Verify the data:

```sql
SELECT p.name, p.sku, p.price, c.name AS category
FROM   products p
JOIN   categories c ON c.category_id = p.category_id
ORDER  BY c.name, p.name;
```

You should see all seven products with their category names.

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
| Artifact | `catalog` |
| Packaging | Jar |
| Java | 17 |

Also choose `yaml` for the configuration format.

Add the following dependencies:

- **Spring Web**
- **Spring Data JPA**
- **Oracle Driver**
- **Spring Boot DevTools**
- **Validation**

Click **Generate**, unzip the archive, and open the project in IntelliJ via **File -> Open -> New Window**.

Wait for Maven to download dependencies. Watch the progress bar at the bottom of the IDE. Do not proceed until it finishes.

### Step 2.2 - Configure the datasource

Open `application.yaml` and add the following. Replace the password if yours differs.

**==> NOTE: If you are using Docker, change the port to 1522 instead of 1521**

```yaml
spring:
  datasource:
    url: jdbc:oracle:thin:@localhost:1521/XEPDB1
    username: labuser
    password: labpass123
    driver-class-name: oracle.jdbc.OracleDriver

  jpa:
    database-platform: org.hibernate.dialect.OracleDialect
    hibernate:
      ddl-auto: validate
    show-sql: true
    properties:
      hibernate:
        format_sql: true
```


Two settings here warrant explanation:

`ddl-auto: validate` tells Hibernate to compare its entity model against the actual database tables at startup. If the mapping does not match the schema, the application refuses to start and reports which column or table is missing. It never creates or drops anything. This is the appropriate setting when you own your DDL.

`show-sql: true` and `format_sql: true` together print every SQL statement Hibernate sends to Oracle to the IntelliJ console. Keep these on throughout the lab. You will use the output to understand what Hibernate is actually doing.

### Step 2.3 - Create the package structure

Right-click `src/main/java/com/example/catalog` in the Project panel and create these sub-packages:

```
com.example.catalog
├── controller
├── dto
├── entity
├── repository
└── service
```

---


## Part 3 - Map the Entity Classes

> Note:
> There are a number of TODO comments in the provided code. These are *not* places to add code, all the code is already there. The purpose of the TODOs is to direct your attention to important JPA annotations and behaviours. Read the comment, understand the concept, then review the code that is already present. Explanations for the code almost all of the TODOs is in the solutions file. 
> 
> 
### Step 3.1 - Create the Category entity

Create `Category.java` in the `entity` package:

```java
package com.example.catalog.entity;

import jakarta.persistence.*;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "categories")
public class Category {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "category_id")
    private Long categoryId;

    @Column(name = "name", nullable = false, length = 100)
    private String name;

    @Column(name = "description", length = 500)
    private String description;

    @Column(name = "created_date")
    private LocalDate createdDate;

    // TODO 1: Add the @OneToMany mapping to the products field below.
    // Use mappedBy = "category" (this refers to the field name on Product, not the column name).
    // Use FetchType.LAZY -- this is the default but declare it explicitly so the intent is clear.
    // Use cascade = CascadeType.ALL so saving a Category also saves its Products.
    @OneToMany(mappedBy = "category", fetch = FetchType.LAZY, cascade = CascadeType.ALL)
    private List<Product> products = new ArrayList<>();

    // Constructors

    public Category() {}

    public Category(String name, String description) {
        this.name = name;
        this.description = description;
    }

    // Getters and setters

    public Long getCategoryId() { return categoryId; }
    public void setCategoryId(Long categoryId) { this.categoryId = categoryId; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }

    public LocalDate getCreatedDate() { return createdDate; }
    public void setCreatedDate(LocalDate createdDate) { this.createdDate = createdDate; }

    public List<Product> getProducts() { return products; }
    public void setProducts(List<Product> products) { this.products = products; }
}
```

### Step 3.2 - Create the Product entity

Create `Product.java` in the `entity` package:

```java
package com.example.catalog.entity;

import jakarta.persistence.*;
import java.math.BigDecimal;

@Entity
@Table(name = "products")
public class Product {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "product_id")
    private Long productId;

    // TODO 2: Add the @ManyToOne mapping for the category field.
    // Use fetch = FetchType.LAZY.
    // Add @JoinColumn(name = "category_id", nullable = false).
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "category_id", nullable = false)
    private Category category;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "sku", unique = true, nullable = false, length = 50)
    private String sku;

    @Column(name = "price", nullable = false, precision = 10, scale = 2)
    private BigDecimal price;

    @Column(name = "stock_qty", nullable = false)
    private Integer stockQty = 0;

    @Column(name = "active", nullable = false)
    private Boolean active = true;

    // Constructors

    public Product() {}

    public Product(Category category, String name, String sku, BigDecimal price) {
        this.category = category;
        this.name = name;
        this.sku = sku;
        this.price = price;
    }

    // Getters and setters

    public Long getProductId() { return productId; }
    public void setProductId(Long productId) { this.productId = productId; }

    public Category getCategory() { return category; }
    public void setCategory(Category category) { this.category = category; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getSku() { return sku; }
    public void setSku(String sku) { this.sku = sku; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    public Integer getStockQty() { return stockQty; }
    public void setStockQty(Integer stockQty) { this.stockQty = stockQty; }

    public Boolean getActive() { return active; }
    public void setActive(Boolean active) { this.active = active; }
}
```

### Step 3.3 - Start the application and read the startup log

Run `CatalogApplication.java`. Watch the IntelliJ console carefully.

Because `ddl-auto=validate`, Hibernate will:

1. Query Oracle's data dictionary to read the actual column definitions of `CATEGORIES` and `PRODUCTS`
2. Compare those definitions against the fields on your entity classes
3. Either start cleanly or throw a `SchemaManagementException` if something does not match

A successful start looks like this in the console (the exact SQL will vary):

```
HibernateJpaVendorAdapter - Hibernate ORM core version ...
SchemaValidator - Validated schema for table [categories]
SchemaValidator - Validated schema for table [products]
Started CatalogApplication in X.XXX seconds
```

If you see a `SchemaManagementException`, the most common cause is a column name mismatch between your `@Column(name = ...)` annotation and the actual Oracle column name. Compare the error message to the DDL from Step 1.2 and correct the annotation.

---

## Part 4 - Declare the Repositories

### Step 4.1 - Create the CategoryRepository

Create `CategoryRepository.java` in the `repository` package:

```java
package com.example.catalog.repository;

import com.example.catalog.entity.Category;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface CategoryRepository extends JpaRepository<Category, Long> {

    // TODO 3: Add a derived query method that finds a Category by its name field.
    // The method signature should be:
    //   Optional<Category> findByName(String name);
    // Spring Data will parse "findByName" and generate:
    //   SELECT c FROM Category c WHERE c.name = :name
    Optional<Category> findByName(String name);

    // TODO 4: Add a native query that returns all categories ordered by name.
    // Use @Query(value = "...", nativeQuery = true).
    // Native queries use Oracle SQL syntax and column names, not Java field names.
    @Query(value = "SELECT * FROM categories ORDER BY name ASC", nativeQuery = true)
    List<Category> findAllOrderedByName();
}
```

### Step 4.2 - Create the ProductRepository

Create `ProductRepository.java` in the `repository` package:

```java
package com.example.catalog.repository;

import com.example.catalog.entity.Product;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;

@Repository
public interface ProductRepository extends JpaRepository<Product, Long> {

    // Derived query: Spring Data generates WHERE sku = :sku from the method name
    Optional<Product> findBySku(String sku);

    // Derived query with two conditions: WHERE active = :active AND category.categoryId = :categoryId
    List<Product> findByActiveAndCategoryCategoryId(Boolean active, Long categoryId);

    // Derived query with a price range: WHERE price BETWEEN :min AND :max
    List<Product> findByPriceBetween(BigDecimal min, BigDecimal max);

    // TODO 5: Add a JPQL query that fetches products and eagerly joins their category
    // in a single SQL statement. This prevents the N+1 problem when you later need
    // category data alongside the product.
    //
    // JPQL operates on Java class and field names, not table and column names.
    // The query is:
    //   SELECT p FROM Product p JOIN FETCH p.category WHERE p.active = true
    //
    // Use @Query("...") without nativeQuery = true.
    @Query("SELECT p FROM Product p JOIN FETCH p.category WHERE p.active = true")
    List<Product> findAllActiveWithCategory();

    // TODO 6: Add a native Oracle SQL query that returns the top 5 most expensive
    // active products. Use FETCH FIRST syntax (Oracle 12c+).
    // Mark it with @Query(value = "...", nativeQuery = true).
    @Query(value = """
            SELECT * FROM products
            WHERE  active = 1
            ORDER  BY price DESC
            FETCH  FIRST 5 ROWS ONLY
            """, nativeQuery = true)
    List<Product> findTop5MostExpensive();
}
```

---

## Part 5 - Define the DTOs

Returning JPA entity objects directly from a REST controller is a common anti-pattern. The entity's field set is driven by the database schema, not by what the API consumer needs. Exposing entities also risks accidentally serializing lazy-loaded associations, which triggers additional queries or throws a `LazyInitializationException` after the session closes.

Use dedicated DTO (Data Transfer Object) classes for responses.

### Step 5.1 - Create CategoryDto

Create `CategoryDto.java` in the `dto` package:

```java
package com.example.catalog.dto;

public class CategoryDto {

    private Long categoryId;
    private String name;
    private String description;

    // Constructor used by the service layer to map from the entity
    public CategoryDto(Long categoryId, String name, String description) {
        this.categoryId = categoryId;
        this.name = name;
        this.description = description;
    }

    public Long getCategoryId() { return categoryId; }
    public String getName() { return name; }
    public String getDescription() { return description; }
}
```

### Step 5.2 - Create ProductDto

Create `ProductDto.java` in the `dto` package:

```java
package com.example.catalog.dto;

import java.math.BigDecimal;

public class ProductDto {

    private Long productId;
    private String name;
    private String sku;
    private BigDecimal price;
    private Integer stockQty;
    private Boolean active;
    private String categoryName;  // flattened from the Category association

    public ProductDto(Long productId, String name, String sku,
                      BigDecimal price, Integer stockQty,
                      Boolean active, String categoryName) {
        this.productId = productId;
        this.name = name;
        this.sku = sku;
        this.price = price;
        this.stockQty = stockQty;
        this.active = active;
        this.categoryName = categoryName;
    }

    public Long getProductId() { return productId; }
    public String getName() { return name; }
    public String getSku() { return sku; }
    public BigDecimal getPrice() { return price; }
    public Integer getStockQty() { return stockQty; }
    public Boolean getActive() { return active; }
    public String getCategoryName() { return categoryName; }
}
```

### Step 5.3 - Create ProductCreateRequest

Create `ProductCreateRequest.java` in the `dto` package. This is the inbound request body for creating a new product.

```java
package com.example.catalog.dto;

import jakarta.validation.constraints.*;
import java.math.BigDecimal;

public class ProductCreateRequest {

    @NotNull
    private Long categoryId;

    @NotBlank
    @Size(max = 200)
    private String name;

    @NotBlank
    @Size(max = 50)
    private String sku;

    @NotNull
    @DecimalMin(value = "0.01")
    private BigDecimal price;

    @NotNull
    @Min(0)
    private Integer stockQty;

    public Long getCategoryId() { return categoryId; }
    public void setCategoryId(Long categoryId) { this.categoryId = categoryId; }

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }

    public String getSku() { return sku; }
    public void setSku(String sku) { this.sku = sku; }

    public BigDecimal getPrice() { return price; }
    public void setPrice(BigDecimal price) { this.price = price; }

    public Integer getStockQty() { return stockQty; }
    public void setStockQty(Integer stockQty) { this.stockQty = stockQty; }
}
```

---

## Part 6 - Implement the Service Layer

### Step 6.1 - Create ProductService

Create `ProductService.java` in the `service` package. This is where the transaction boundaries live.

```java
package com.example.catalog.service;

import com.example.catalog.dto.ProductCreateRequest;
import com.example.catalog.dto.ProductDto;
import com.example.catalog.entity.Category;
import com.example.catalog.entity.Product;
import com.example.catalog.repository.CategoryRepository;
import com.example.catalog.repository.ProductRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
public class ProductService {

    private final ProductRepository productRepository;
    private final CategoryRepository categoryRepository;

    public ProductService(ProductRepository productRepository,
                          CategoryRepository categoryRepository) {
        this.productRepository = productRepository;
        this.categoryRepository = categoryRepository;
    }

    // Read-only transaction: JPA skips dirty checking, Oracle can optimise locking
    @Transactional(readOnly = true)
    public List<ProductDto> findAllActive() {
        // TODO 7: Call productRepository.findAllActiveWithCategory() to fetch active
        // products with their category in a single JOIN FETCH query.
        // Map each Product to a ProductDto using the private toDto() method below.
        // Return the mapped list.
        return productRepository.findAllActiveWithCategory()
                .stream()
                .map(this::toDto)
                .toList();
    }

    @Transactional(readOnly = true)
    public ProductDto findById(Long id) {
        // TODO 8: Use productRepository.findById(id).
        // If the Optional is empty, throw new NoSuchElementException("Product not found: " + id).
        // Otherwise map and return the ProductDto.
        return productRepository.findById(id)
                .map(this::toDto)
                .orElseThrow(() -> new NoSuchElementException("Product not found: " + id));
    }

    @Transactional
    public ProductDto create(ProductCreateRequest request) {
        // TODO 9: Load the Category from categoryRepository.findById(request.getCategoryId()).
        // If absent, throw NoSuchElementException("Category not found: " + request.getCategoryId()).
        //
        // Construct a new Product entity:
        //   product.setCategory(category);
        //   product.setName(request.getName());
        //   product.setSku(request.getSku());
        //   product.setPrice(request.getPrice());
        //   product.setStockQty(request.getStockQty());
        //
        // Call productRepository.save(product) and return the mapped DTO.
        //
        // Note: the product is new (not yet managed), so save() is required here.
        // After the first save(), the entity becomes managed for the rest of this transaction.
        Category category = categoryRepository.findById(request.getCategoryId())
                .orElseThrow(() -> new NoSuchElementException(
                        "Category not found: " + request.getCategoryId()));

        Product product = new Product();
        product.setCategory(category);
        product.setName(request.getName());
        product.setSku(request.getSku());
        product.setPrice(request.getPrice());
        product.setStockQty(request.getStockQty());

        Product saved = productRepository.save(product);
        return toDto(saved);
    }

    @Transactional
    public ProductDto adjustStock(Long id, int delta) {
        // TODO 10: Load the product by ID (throw NoSuchElementException if absent).
        //
        // Update the stock quantity:
        //   product.setStockQty(product.getStockQty() + delta);
        //
        // DO NOT call productRepository.save().
        //
        // Because the product is now a MANAGED entity inside this @Transactional method,
        // Hibernate's dirty checking will detect the field change automatically and issue
        // an UPDATE when the transaction commits. You do not need an explicit save() call.
        //
        // After completing the TODO, add a System.out.println before the return:
        //   System.out.println("No explicit save() called -- dirty checking handles the UPDATE");
        // Run the endpoint and verify the UPDATE appears in the console log anyway.
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Product not found: " + id));

        product.setStockQty(product.getStockQty() + delta);

        System.out.println("No explicit save() called -- dirty checking handles the UPDATE");
        return toDto(product);
    }

    @Transactional
    public void deactivate(Long id) {
        Product product = productRepository.findById(id)
                .orElseThrow(() -> new NoSuchElementException("Product not found: " + id));
        product.setActive(false);
        // Again: no save() needed. Dirty checking will issue the UPDATE.
    }

    // Private mapping helper. Accesses product.getCategory().getName(),
    // which is safe here because this method is always called inside
    // an open transaction (the caller's @Transactional boundary).
    private ProductDto toDto(Product product) {
        return new ProductDto(
                product.getProductId(),
                product.getName(),
                product.getSku(),
                product.getPrice(),
                product.getStockQty(),
                product.getActive(),
                product.getCategory().getName()   // triggers lazy load if not already fetched
        );
    }
}
```

### Step 6.2 - Create CategoryService

Create `CategoryService.java` in the `service` package:

```java
package com.example.catalog.service;

import com.example.catalog.dto.CategoryDto;
import com.example.catalog.entity.Category;
import com.example.catalog.repository.CategoryRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.NoSuchElementException;

@Service
public class CategoryService {

    private final CategoryRepository categoryRepository;

    public CategoryService(CategoryRepository categoryRepository) {
        this.categoryRepository = categoryRepository;
    }

    @Transactional(readOnly = true)
    public List<CategoryDto> findAll() {
        return categoryRepository.findAllOrderedByName()
                .stream()
                .map(this::toDto)
                .toList();
    }

    @Transactional(readOnly = true)
    public CategoryDto findById(Long id) {
        return categoryRepository.findById(id)
                .map(this::toDto)
                .orElseThrow(() -> new NoSuchElementException("Category not found: " + id));
    }

    @Transactional
    public CategoryDto create(String name, String description) {
        // TODO 11: Check whether a category with this name already exists
        // using categoryRepository.findByName(name).
        // If present, throw new IllegalArgumentException("Category already exists: " + name).
        // Otherwise construct a new Category entity, call categoryRepository.save(), and return the DTO.
        categoryRepository.findByName(name).ifPresent(existing -> {
            throw new IllegalArgumentException("Category already exists: " + name);
        });

        Category category = new Category(name, description);
        Category saved = categoryRepository.save(category);
        return toDto(saved);
    }

    private CategoryDto toDto(Category category) {
        return new CategoryDto(
                category.getCategoryId(),
                category.getName(),
                category.getDescription()
        );
    }
}
```

---

## Part 7 - Implement the Controllers

### Step 7.1 - Create ProductController

Create `ProductController.java` in the `controller` package:

```java
package com.example.catalog.controller;

import com.example.catalog.dto.ProductCreateRequest;
import com.example.catalog.dto.ProductDto;
import com.example.catalog.service.ProductService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/v1/products")
public class ProductController {

    private final ProductService productService;

    public ProductController(ProductService productService) {
        this.productService = productService;
    }

    @GetMapping
    public List<ProductDto> getAll() {
        return productService.findAllActive();
    }

    @GetMapping("/{id}")
    public ResponseEntity<ProductDto> getById(@PathVariable Long id) {
        try {
            return ResponseEntity.ok(productService.findById(id));
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }

    @PostMapping
    public ResponseEntity<ProductDto> create(@Valid @RequestBody ProductCreateRequest request) {
        try {
            ProductDto created = productService.create(request);
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (NoSuchElementException e) {
            return ResponseEntity.badRequest().build();
        }
    }

    // TODO 12: Implement the PATCH /api/v1/products/{id}/stock endpoint.
    // It should read a "delta" integer from the request body (use Map<String, Integer>).
    // Call productService.adjustStock(id, delta) and return 200 OK with the updated DTO.
    // Return 404 if the product is not found.
    @PatchMapping("/{id}/stock")
    public ResponseEntity<ProductDto> adjustStock(@PathVariable Long id,
                                                  @RequestBody Map<String, Integer> body) {
        try {
            int delta = body.getOrDefault("delta", 0);
            return ResponseEntity.ok(productService.adjustStock(id, delta));
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> deactivate(@PathVariable Long id) {
        try {
            productService.deactivate(id);
            return ResponseEntity.noContent().build();
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }
}
```

### Step 7.2 - Create CategoryController

Create `CategoryController.java` in the `controller` package:

```java
package com.example.catalog.controller;

import com.example.catalog.dto.CategoryDto;
import com.example.catalog.service.CategoryService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.NoSuchElementException;

@RestController
@RequestMapping("/api/v1/categories")
public class CategoryController {

    private final CategoryService categoryService;

    public CategoryController(CategoryService categoryService) {
        this.categoryService = categoryService;
    }

    @GetMapping
    public List<CategoryDto> getAll() {
        return categoryService.findAll();
    }

    @GetMapping("/{id}")
    public ResponseEntity<CategoryDto> getById(@PathVariable Long id) {
        try {
            return ResponseEntity.ok(categoryService.findById(id));
        } catch (NoSuchElementException e) {
            return ResponseEntity.notFound().build();
        }
    }

    // TODO 13: Implement POST /api/v1/categories.
    // Read "name" and "description" from the request body (use Map<String, String>).
    // Call categoryService.create(name, description).
    // Return 201 CREATED with the CategoryDto body.
    // Return 400 BAD REQUEST if an IllegalArgumentException is thrown (duplicate name).
    @PostMapping
    public ResponseEntity<CategoryDto> create(@RequestBody Map<String, String> body) {
        try {
            String name = body.get("name");
            String description = body.get("description");
            CategoryDto created = categoryService.create(name, description);
            return ResponseEntity.status(HttpStatus.CREATED).body(created);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().build();
        }
    }
}
```

---

## Part 8 - Test the Application

### Step 8.1 - Start the application and read the SQL log

Run `CatalogApplication.java`. You will see Hibernate's validation queries in the console, followed by the Spring Boot startup banner.

Once started, confirm it is listening: open `http://localhost:8080/api/v1/categories` in a browser. You should see a JSON array of the three categories inserted in Part 1.

### Step 8.2 - Create an HTTP test file

Create `catalog-tests.http` in the project root:

```http
### List all categories (ordered by name - native query)
GET http://localhost:8080/api/v1/categories

###

### Get a single category
GET http://localhost:8080/api/v1/categories/1

###

### List all active products (JOIN FETCH query - one SQL statement)
GET http://localhost:8080/api/v1/products

###

### Get a single product
GET http://localhost:8080/api/v1/products/1

###

### Create a new product
POST http://localhost:8080/api/v1/products
Content-Type: application/json

{
  "categoryId": 1,
  "name": "Mechanical Keyboard TKL",
  "sku": "KBD-MK-008",
  "price": 89.99,
  "stockQty": 60
}

###

### Adjust stock (delta can be positive or negative)
PATCH http://localhost:8080/api/v1/products/1/stock
Content-Type: application/json

{
  "delta": -5
}

###

### Deactivate a product (soft delete)
DELETE http://localhost:8080/api/v1/products/7

###

### Create a duplicate category to trigger the duplicate check
POST http://localhost:8080/api/v1/categories
Content-Type: application/json

{
  "name": "Electronics",
  "description": "Duplicate attempt"
}

###

### Create a new category successfully
POST http://localhost:8080/api/v1/categories
Content-Type: application/json

{
  "name": "Peripherals",
  "description": "Keyboards, mice, and monitors"
}
```

Execute each request using the IntelliJ HTTP Client (the green play icon next to each `###` line). After each request, read the SQL output in the console.

### Step 8.3 - Observe the SQL that Hibernate generates

Run the **List all active products** request and read the console output. You should see exactly one SELECT statement, including a JOIN, because `findAllActiveWithCategory()` uses `JOIN FETCH`:

```sql
SELECT p1_0.product_id,
       p1_0.active,
       c1_0.category_id,
       c1_0.created_date,
       c1_0.description,
       c1_0.name,
       p1_0.name,
       p1_0.price,
       p1_0.sku,
       p1_0.stock_qty
FROM   products p1_0
JOIN   categories c1_0 ON c1_0.category_id = p1_0.category_id
WHERE  p1_0.active = 1
```

One query. All seven products. All category names. This is what you want.

### Step 8.4 - Run the stock adjustment and observe dirty checking

Run the **Adjust stock** request. In the console you will see your `System.out.println` message followed by an UPDATE that Hibernate issued even though your code never called `save()`:

```sql
update products
set    active=?,
       category_id=?,
       name=?,
       price=?,
       sku=?,
       stock_qty=?
where  product_id=?
```

Hibernate detected that `stockQty` changed between when the entity was loaded and when the transaction committed. It generated the UPDATE automatically. This is dirty checking in action.

---

## (Challenge) Part 9 - Observe and Fix the N+1 Problem

This part demonstrates the most common JPA performance mistake and shows you how to diagnose and correct it.

### Step 9.1 - Create a broken endpoint that triggers N+1

Add the following method to `ProductRepository`:

```java
// This method does NOT use JOIN FETCH -- it returns products without their category
List<Product> findByActiveTrue();
```

Add the following method to `ProductService`:

```java
@Transactional(readOnly = true)
public List<ProductDto> findAllActiveNPlusOne() {
    // WARNING: this method demonstrates the N+1 problem.
    // It loads products without their category, then accesses
    // product.getCategory() in toDto(), which fires one additional
    // SELECT per product.
    return productRepository.findByActiveTrue()
            .stream()
            .map(this::toDto)
            .toList();
}
```

Add the following endpoint to `ProductController`:

```java
@GetMapping("/n-plus-one-demo")
public List<ProductDto> nPlusOneDemo() {
    return productService.findAllActiveNPlusOne();
}
```

### Step 9.2 - Run the broken endpoint and count the queries

Add to `catalog-tests.http`:

```http
### N+1 demo -- watch the console
GET http://localhost:8080/api/v1/products/n-plus-one-demo
```

Execute it. Count the SELECT statements in the IntelliJ console. With seven active products you will see:

- 1 SELECT to load all products (no category join)
- 7 additional SELECTs, one per product, to load each category when `toDto()` accesses `product.getCategory().getName()`

That is 8 queries where 1 would suffice. In a table with 1000 products this becomes 1001 queries.

### Step 9.3 - Understand why this happens

When Hibernate loads a product from the database with lazy loading on the category association, it does not fetch the category row. Instead it installs a proxy object in the `category` field. That proxy looks like a real `Category` to your Java code, but it has no data. The first time your code calls any method on the proxy (such as `getName()`), Hibernate fires a SELECT to load the real category from Oracle.

Because `toDto()` calls `product.getCategory().getName()` for every product in the list, and each product has its own proxy pointing at potentially a different category, Hibernate fires a SELECT for each one.

### Step 9.4 - Confirm the fix

The `findAllActiveWithCategory()` method in `ProductRepository` already contains the fix: `JOIN FETCH p.category`. Run the original `/api/v1/products` endpoint again and confirm you still see exactly one query. The `findByActiveTrue()` method and its N+1 path are left in place for comparison.

---

## Checkpoints

Answer these in writing or discuss with your instructor before closing the lab.

1. In `adjustStock()` you changed `stockQty` and did not call `save()`. The UPDATE still executed. Explain exactly when Hibernate detects the change and when it sends the UPDATE to Oracle.

2. The `@Transactional(readOnly = true)` annotation is on several service methods. It does two things: it tells the Spring transaction manager to open a read-only transaction, and it gives Hibernate permission to skip dirty checking entirely. Why is skipping dirty checking a meaningful performance improvement in a method that returns a large list?

3. `findAllActiveWithCategory()` uses JPQL with `JOIN FETCH`. `findTop5MostExpensive()` uses a native SQL query. Give one reason you would choose native SQL over JPQL for a specific query in an Oracle application.

4. The `toDto()` helper method accesses `product.getCategory().getName()`. This is safe in the service methods here because they are all `@Transactional`. What would happen if `toDto()` were called from inside the controller, after the service transaction had already closed? What exception would you see and why?

5. `ProductRepository` extends `JpaRepository<Product, Long>`. The `Long` type parameter is the type of the primary key. What would happen at application startup if you used `Integer` instead of `Long` while the Oracle column was defined as `NUMBER GENERATED AS IDENTITY`?

---

## Challenge Exercises

Complete these independently. No solution is provided.

### Challenge 1 - Price range search endpoint

Add a GET endpoint at `/api/v1/products/search` that accepts `minPrice` and `maxPrice` as query parameters and returns the matching products. Use the existing `findByPriceBetween` derived query in the repository. Handle missing or invalid parameters gracefully.

### Challenge 2 - Products by category

Add a GET endpoint at `/api/v1/categories/{id}/products` that returns all active products in the given category. Use the derived query `findByActiveAndCategoryCategoryId` in `ProductRepository`. Return 404 if the category does not exist.

### Challenge 3 - Bidirectional traversal

The `Category` entity has a `List<Product>` field mapped with `@OneToMany`. Add a GET endpoint at `/api/v1/categories/{id}/summary` that returns the category name and the count of active products in it. Implement this without writing a new query: load the category with its products list and count in Java. Then consider what the implications are for a category with 50,000 products, and describe a better approach using `@Query`.

### Challenge 4 - Observe the entity lifecycle states

Add a `@PostConstruct` method to a new `@Component` class that:

1. Uses the `EntityManager` directly (inject via `@PersistenceContext`) to find a product by ID
2. Prints "Entity state: MANAGED"
3. Calls `entityManager.detach(product)`
4. Prints "Entity state: DETACHED"
5. Modifies a field on the detached product and calls `entityManager.merge(product)`
6. Prints "Entity state: MANAGED (after merge)"

Read the Hibernate SQL output at startup. This exercise makes the entity lifecycle states from the lecture slides concrete.

---

## Lab Summary

In this lab you:

- Created Oracle tables with primary keys using `GENERATED AS IDENTITY` and a foreign key constraint
- Mapped those tables to JPA entity classes using `@Entity`, `@Table`, `@Id`, `@GeneratedValue`, `@Column`, `@ManyToOne`, and `@OneToMany`
- Declared repository interfaces and observed Spring Data generate proxy implementations at startup
- Used derived query methods (`findBySku`, `findByPriceBetween`) and both JPQL and native queries via `@Query`
- Observed Hibernate's dirty checking issue an UPDATE without an explicit `save()` call
- Observed the N+1 query problem by loading lazy associations in a loop and fixed it with `JOIN FETCH`
- Placed `@Transactional` boundaries in the service layer and explained why they belong there rather than in the repository or controller

---

*End of Lab 3.3*
