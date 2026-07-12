# Lab 3.3 - Solutions Reference

**MD282 | Week 3 - Oracle Data, PL/SQL and Performance Engineering**
**Module 5 | Spring Data JPA with Oracle**

---

> **How to use this file**
>
> Work through the lab on your own first. Use this file only when you are stuck on a specific TODO or want to verify that your answer is correct. Each solution includes an explanation of why the code is written the way it is, not just what to write. Reading the explanation is as important as reading the code.
>
> Solutions to the checkpoint questions are at the bottom.

---

## TODO 1 - @OneToMany on Category

**Location:** `Category.java`, `entity` package

**The task:** Add the `@OneToMany` mapping to the `products` field.

```java
@OneToMany(mappedBy = "category", fetch = FetchType.LAZY, cascade = CascadeType.ALL)
private List<Product> products = new ArrayList<>();
```

**Why each attribute is there:**

`mappedBy = "category"` tells JPA that the `Product` entity owns this relationship, and that the foreign key column lives on the `products` table, not the `categories` table. The value `"category"` refers to the field name on the `Product` class, not to the database column name. If you omit `mappedBy`, JPA assumes this side owns the relationship and tries to create a join table, which does not match your schema.

`fetch = FetchType.LAZY` is already the default for `@OneToMany`, but declaring it explicitly makes the intent visible to any developer reading the class. Lazy loading means the list of products is not fetched from Oracle unless your code actually calls `getProducts()`. For categories that may have thousands of products, this matters enormously.

`cascade = CascadeType.ALL` means that if you save, merge, or delete a `Category` through its repository, JPA applies the same operation to every `Product` in its list. For this lab the cascade is included for completeness, but in a production system you would think carefully before using `CascadeType.ALL` on a one-to-many relationship, because a `delete` on a category would cascade to all its products automatically.

---

## TODO 2 - @ManyToOne on Product

**Location:** `Product.java`, `entity` package

**The task:** Add the `@ManyToOne` mapping and `@JoinColumn` to the `category` field.

```java
@ManyToOne(fetch = FetchType.LAZY)
@JoinColumn(name = "category_id", nullable = false)
private Category category;
```

**Why each attribute is there:**

`@ManyToOne` marks this side as the owning side of the relationship. Because `Product` holds the `category_id` foreign key column in Oracle, `Product` is the owner. JPA uses this annotation to know which table holds the foreign key.

`fetch = FetchType.LAZY` is important here. The default for `@ManyToOne` is `FetchType.EAGER`, which would load the `Category` row automatically every time you load a `Product`. That sounds convenient, but if you load 500 products in a list query, JPA would execute 500 additional SELECTs to fetch categories, or add a JOIN that you may not always want. Declaring `LAZY` means the category is only loaded when your code accesses `product.getCategory()`.

`@JoinColumn(name = "category_id", nullable = false)` tells Hibernate that the foreign key column in the `products` table is named `category_id`, and that it cannot be null. Without `@JoinColumn`, Hibernate guesses the column name from the field name, which usually works but is fragile. Always be explicit.

---

## TODO 3 - findByName derived query

**Location:** `CategoryRepository.java`, `repository` package

**The task:** Add a derived query method that finds a `Category` by its `name` field.

```java
Optional<Category> findByName(String name);
```

**Why this works:**

Spring Data reads the method name `findByName` at startup and parses it. `findBy` is the subject (a SELECT query). `Name` maps to the `name` field on the `Category` entity. Spring Data generates the JPQL `SELECT c FROM Category c WHERE c.name = :name` and wraps the result in an `Optional`. You write nothing else.

Returning `Optional<Category>` is the correct choice here because a category with that name may not exist. Never return a nullable entity directly from a repository method when `Optional` is available.

---

## TODO 4 - Native query for ordered categories

**Location:** `CategoryRepository.java`, `repository` package

**The task:** Add a native Oracle SQL query that returns all categories ordered by name.

```java
@Query(value = "SELECT * FROM categories ORDER BY name ASC", nativeQuery = true)
List<Category> findAllOrderedByName();
```

**Why `nativeQuery = true`:**

Without `nativeQuery = true`, `@Query` expects JPQL, which operates on Java class and field names rather than table and column names. The JPQL equivalent would be `SELECT c FROM Category c ORDER BY c.name ASC`. Both produce the same SQL, but the native query form is used here to illustrate the difference and to show that you can drop down to Oracle SQL whenever you need syntax that JPQL cannot express, such as Oracle-specific hints, analytic functions, or `FETCH FIRST`.

---

## TODO 5 - JPQL JOIN FETCH query

**Location:** `ProductRepository.java`, `repository` package

**The task:** Add a JPQL query that loads active products and eagerly joins their category in a single SQL statement.

```java
@Query("SELECT p FROM Product p JOIN FETCH p.category WHERE p.active = true")
List<Product> findAllActiveWithCategory();
```

**Why JOIN FETCH:**

Without `JOIN FETCH`, a query that returns a list of products would load each product's category lazily, triggering one extra SELECT per product when `toDto()` accesses `product.getCategory().getName()`. That is the N+1 problem demonstrated in Part 9.

`JOIN FETCH p.category` instructs Hibernate to join the `categories` table in the same SQL statement and populate the `category` field on each `Product` immediately. When `toDto()` later calls `getCategory().getName()`, the data is already in memory and no additional database round trip occurs.

Note that the query references `p.category` (the Java field name on `Product`) and `p.active` (the Java field name), not the Oracle column names `category_id` or `active`. JPQL always operates on the Java model.

---

## TODO 6 - Native query for top 5 most expensive products

**Location:** `ProductRepository.java`, `repository` package

**The task:** Add a native Oracle SQL query that returns the top 5 most expensive active products.

```java
@Query(value = """
        SELECT * FROM products
        WHERE  active = 1
        ORDER  BY price DESC
        FETCH  FIRST 5 ROWS ONLY
        """, nativeQuery = true)
List<Product> findTop5MostExpensive();
```

**Why native SQL here:**

`FETCH FIRST n ROWS ONLY` is Oracle 12c+ syntax. JPQL does not have a direct equivalent that maps to this specific Oracle construct. You can use `Pageable` with Spring Data pagination to limit results portably, but `FETCH FIRST` is cleaner and more explicit when you simply want a fixed top-N result from Oracle. Native queries are the right tool when you need Oracle-specific SQL that JPQL cannot express.

Note that `active = 1` is used rather than `active = true` because Oracle stores the boolean-mapped column as a `NUMBER(1)` and does not recognise the literal `true` in native SQL.

---

## TODO 7 - findAllActive in ProductService

**Location:** `ProductService.java`, `service` package

**The task:** Implement `findAllActive()` using `findAllActiveWithCategory()` and map to DTOs.

```java
@Transactional(readOnly = true)
public List<ProductDto> findAllActive() {
    return productRepository.findAllActiveWithCategory()
            .stream()
            .map(this::toDto)
            .toList();
}
```

**Why `readOnly = true`:**

`@Transactional(readOnly = true)` does two things. It tells the Spring transaction manager to open a read-only transaction, which allows Oracle to optimise locking. More importantly for performance, it tells Hibernate it can skip dirty checking entirely. In a read-only method that returns a large list, skipping dirty checking means Hibernate does not need to take a snapshot of every entity it loads and compare each one at commit time. For a query returning 500 products, that is 500 fewer comparison operations at the end of the transaction.

---

## TODO 8 - findById in ProductService

**Location:** `ProductService.java`, `service` package

**The task:** Implement `findById()`, throwing `NoSuchElementException` if the product does not exist.

```java
@Transactional(readOnly = true)
public ProductDto findById(Long id) {
    return productRepository.findById(id)
            .map(this::toDto)
            .orElseThrow(() -> new NoSuchElementException("Product not found: " + id));
}
```

**Why this pattern:**

`findById()` returns an `Optional<Product>`. Calling `.map(this::toDto)` converts the `Product` to a `ProductDto` inside the `Optional` if it is present, leaving an empty `Optional` unchanged. `orElseThrow()` then either unwraps the value or throws the exception. This is the idiomatic Java Optional chain and avoids an explicit null check.

The `toDto()` call happens inside the `@Transactional` boundary, which means the Hibernate session is still open when `toDto()` accesses `product.getCategory().getName()`. If the product was loaded with `JOIN FETCH`, no extra query fires. If it was loaded without `JOIN FETCH`, Hibernate fires one lazy SELECT for the category at that point. Either way, the session is open and no `LazyInitializationException` is thrown.

---

## TODO 9 - create in ProductService

**Location:** `ProductService.java`, `service` package

**The task:** Load the category, build a new `Product`, call `save()`, and return the DTO.

```java
@Transactional
public ProductDto create(ProductCreateRequest request) {
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
```

**Why `save()` is required here but not in `adjustStock()`:**

A newly constructed `Product` object is in the **transient** state. Hibernate has never seen it and is not tracking it. Calling `save()` transitions it to the **managed** (persistent) state and issues an `INSERT`. After that call, Hibernate tracks the entity for the rest of the transaction.

Contrast this with `adjustStock()` in TODO 10, where the product is loaded from the database by `findById()`. That loaded entity is already managed. Any changes you make to it are detected automatically at commit time. `save()` on a managed entity is a no-op in this scenario.

---

## TODO 10 - adjustStock in ProductService

**Location:** `ProductService.java`, `service` package

**The task:** Load the product, update `stockQty`, and return the DTO without calling `save()`.

```java
@Transactional
public ProductDto adjustStock(Long id, int delta) {
    Product product = productRepository.findById(id)
            .orElseThrow(() -> new NoSuchElementException("Product not found: " + id));

    product.setStockQty(product.getStockQty() + delta);

    System.out.println("No explicit save() called -- dirty checking handles the UPDATE");
    return toDto(product);
}
```

**What you should observe in the console:**

When you run the PATCH endpoint, the IntelliJ console will print your message followed by an UPDATE statement from Hibernate. Hibernate took a snapshot of the product's state when `findById()` loaded it. At the end of the `@Transactional` method, before committing, Hibernate compares the current field values against that snapshot. It detects that `stockQty` changed. It generates and executes the UPDATE automatically. You never called `save()`.

This is dirty checking. It is one of the most important JPA behaviours to understand, and it is also one of the most common sources of confusion for developers who expect data access to be explicit.

---

## TODO 11 - create in CategoryService

**Location:** `CategoryService.java`, `service` package

**The task:** Check for a duplicate name, then save and return the new category.

```java
@Transactional
public CategoryDto create(String name, String description) {
    categoryRepository.findByName(name).ifPresent(existing -> {
        throw new IllegalArgumentException("Category already exists: " + name);
    });

    Category category = new Category(name, description);
    Category saved = categoryRepository.save(category);
    return toDto(saved);
}
```

**Why `ifPresent` with a lambda:**

`findByName()` returns an `Optional<Category>`. `ifPresent()` runs the lambda only if a value is present. This is more concise than writing an `if` block with `.isPresent()` followed by the throw. The lambda throws an unchecked `IllegalArgumentException`, which propagates out of `ifPresent()` and then out of the method entirely, bypassing the save call below.

Note that this duplicate check is not atomic. In a high-concurrency system, two requests could both pass the check simultaneously and both insert a category with the same name. The `UNIQUE` constraint on the name column would catch the second insert with a `DataIntegrityViolationException`. Handling that exception at the controller level would be the next step in a production implementation.

---

## TODO 12 - adjustStock endpoint in ProductController

**Location:** `ProductController.java`, `controller` package

**The task:** Implement the `PATCH /{id}/stock` endpoint.

```java
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
```

**Why `Map<String, Integer>` instead of a dedicated request class:**

For a single-field request body, a `Map` avoids the overhead of creating a dedicated class. It is acceptable for simple cases. For a body with more than one or two fields, or where validation annotations are needed, a dedicated class is cleaner. Here the `getOrDefault("delta", 0)` call provides a sensible default if the caller omits the field.

`PATCH` is the appropriate HTTP verb for a partial update. `PUT` implies replacing the entire resource. Adjusting stock quantity is a partial update, so `PATCH` is correct.

---

## TODO 13 - create endpoint in CategoryController

**Location:** `CategoryController.java`, `controller` package

**The task:** Implement `POST /api/v1/categories`.

```java
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
```

**Why 201 CREATED and not 200 OK:**

`201 CREATED` is the semantically correct HTTP status when a new resource has been created as a result of a POST request. `200 OK` means the request succeeded but does not communicate that something new was created. Many APIs return `200` for everything, but using the correct status codes makes APIs easier to consume programmatically.

The `IllegalArgumentException` thrown by the service when a duplicate name is submitted is caught here and mapped to `400 BAD REQUEST`. The controller is responsible for translating domain exceptions into HTTP responses. The service should never construct `ResponseEntity` objects.

---

## Checkpoint Answers

### Checkpoint 1

> In `adjustStock()` you changed `stockQty` and did not call `save()`. The UPDATE still executed. Explain exactly when Hibernate detects the change and when it sends the UPDATE to Oracle.

When `findById()` loads the `Product`, Hibernate takes a snapshot of every field on the entity and stores it internally. This is called the first-level cache entry. The entity is now in the **managed** state for the duration of the transaction.

When the `@Transactional` method is about to commit, Hibernate performs a **flush**. During the flush, it compares the current field values on every managed entity against the snapshots taken at load time. When it finds that `stockQty` is different, it generates an UPDATE statement and sends it to Oracle. The transaction then commits and the change is durable.

The UPDATE is sent during the flush, which happens before the commit. By default, Spring triggers a flush automatically at the end of a `@Transactional` method. You can also trigger it manually with `entityManager.flush()`, but that is rarely necessary.

---

### Checkpoint 2

> The `@Transactional(readOnly = true)` annotation gives Hibernate permission to skip dirty checking entirely. Why is skipping dirty checking a meaningful performance improvement in a method that returns a large list?

Dirty checking requires Hibernate to keep a snapshot of every managed entity in memory and compare every field of every entity against its snapshot at flush time. If a query returns 500 products, Hibernate allocates memory for 500 snapshots when the entities are loaded. At flush time, it iterates over all 500 entities and compares each field one by one.

In a read-only method, none of the entities will ever be modified. There is nothing to detect and no UPDATE to generate. The snapshot allocation and comparison are entirely wasted work. With `readOnly = true`, Hibernate skips both the snapshot storage and the comparison, reducing memory pressure and eliminating the flush-time comparison loop for every entity in the result set.

---

### Checkpoint 3

> Give one reason you would choose native SQL over JPQL for a specific query in an Oracle application.

Oracle analytic (window) functions such as `ROW_NUMBER() OVER (PARTITION BY ...)`, `RANK()`, `LAG()`, and `LEAD()` have no equivalent in JPQL. If you need to calculate running totals, rank rows within a partition, or compare a row to the previous row, you must use a native query. JPQL is a lowest-common-denominator query language designed to be portable across databases. Oracle's analytical SQL capabilities go well beyond what JPQL can express.

Other valid answers include Oracle hints (`/*+ INDEX(t idx_name) */`), `CONNECT BY` for hierarchical queries, Oracle-specific date functions, and `FETCH FIRST n ROWS WITH TIES`.

---

### Checkpoint 4

> What would happen if `toDto()` were called from inside the controller, after the service transaction had already closed? What exception would you see and why?

You would see a `LazyInitializationException` with a message similar to: `could not initialize proxy - no Session`.

Here is why. The `toDto()` method calls `product.getCategory().getName()`. If the product was loaded without `JOIN FETCH`, its `category` field holds a Hibernate proxy object. That proxy is bound to the Hibernate session (EntityManager) that was active when the product was loaded. The session is open for the duration of the `@Transactional` method in the service layer.

Once the service method returns, Spring closes the session and the transaction commits. The proxy is now detached from any session. When the controller calls `toDto()` and the proxy tries to load the category from Oracle, it looks for a session to execute the query against and finds none. Hibernate throws `LazyInitializationException`.

This is why `toDto()` is always called inside the service method, within the open transaction, and never from the controller.

---

### Checkpoint 5

> What would happen at application startup if you used `Integer` instead of `Long` while the Oracle column was defined as `NUMBER GENERATED AS IDENTITY`?

The application would likely start successfully because the JPA type mapping for `Integer` and `Long` both map to numeric Oracle columns, and the schema validation only checks that the column exists and is of a compatible type.

The problem would appear at runtime when Oracle assigns an identity value larger than `2,147,483,647` (the maximum value of a Java `Integer`). Hibernate would attempt to map the Oracle `NUMBER` value into an `Integer` field and overflow silently or throw an arithmetic exception, depending on the Hibernate version and dialect. In practice on a new lab database this would not cause an immediate failure, but it is a latent defect.

`Long` is the correct type for `NUMBER GENERATED AS IDENTITY` columns in Oracle because Oracle identity columns are backed by sequences, which generate `NUMBER(28)` values by default. `Long` (max value `9,223,372,036,854,775,807`) is safe for any realistic identity sequence.

---

*End of Lab 3.3 Solutions*
