# Lab 1-1: IDE and IntelliJ IDEA amd GitHub Copilot Fundamentals
## Hands-On Exercises

> **Course:** MD282 – Java Full-Stack Development  
> **Module:** 0 – IDE Fundamentals: IntelliJ IDEA & GitHub Copilot  
> **Estimated time per exercise:** 30–45 minutes

---

## How to Use These Exercises

Module 0 is intentionally tool-focused to give you the opportunity to get used to working in IntelliJ IDEA.

Each exercise uses a shared starter project (described in Exercise 1). All subsequent exercises operate on that same project.

> **Note**: The keybindings in these notes may not match the key bindings in your environment. IntelliJ's keymap is highly customizable. To find a specific key shortcut, use Shift-Shift (Search Everywhere) and type the action name (e.g., "Extract Method"). You can also view and edit all key bindings in **File → Settings → Keymap**.

---

## Starter Project

Before beginning the exercises, create the project manually using the steps below.

### Create the project manually in IntelliJ

1. Open IntelliJ IDEA → **File → New → Project**
2. Select **Maven Archetype**, choose SDK **Java 17** 
   - Note: Java 21 is installed on your class VM so you can select that if you prefer, but Java 17 is the most widely used LTS version in industry at the moment
   - Any project that requires Java 17 will work without change in Java 21 because each Java release is backward compatible.
3. Set **GroupId** to `com.example`, **ArtifactId** to `ide-exercises`
4. Click **Create**

Once the project opens, replace the contents of `pom.xml` with:


```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0
         http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.example</groupId>
    <artifactId>ide-exercises</artifactId>
    <version>1.0.0-SNAPSHOT</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.junit.jupiter</groupId>
            <artifactId>junit-jupiter</artifactId>
            <version>5.10.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-surefire-plugin</artifactId>
                <version>3.2.5</version>
            </plugin>
        </plugins>
    </build>
</project>
```

Click the **Maven** icon that appears in the top-right of the editor (or open the Maven tool window and click **Reload**) to download dependencies.

### Creating the package structure

Before adding any source files, you need to create the `com.example.order` package inside the correct source roots. In Maven projects, IntelliJ distinguishes between two source roots:

- `src/main/java` - production source root (blue folder icon)
- `src/test/java` - test source root (green folder icon)

Packages must be created inside the appropriate root, not at the project root level.

**Step 1: Create the production package**

1. In the **Project** tool window (`Alt+1`), expand the project tree until you can see `src/main/java`
2. Right-click on `src/main/java` → **New → Package**
3. Type the full package path: `com.example.order`
4. Press **Enter**

IntelliJ creates all three levels of the hierarchy in one step; you do not need to create `com`, then `example`, then `order` separately. The Project tool window will show the package as `com.example.order` (or `com/example/order` depending on your **Compact Middle Packages** setting both are the same package).

> **Compact Middle Packages:** By default, IntelliJ collapses single-child packages into one node (e.g., `com.example.order` appears as a single entry rather than three nested folders). This is a display setting only, the actual directory structure on disk is always `com/example/order/`. Toggle it with the gear icon in the Project tool window header → **Compact Middle Packages**.

**Step 2: Create the test package**

1. Right-click on `src/test/java` → **New → Package**
2. Type the same package path: `com.example.order`
3. Press **Enter**

It is standard practice in Java projects for test classes to mirror the package structure of the production classes they test. `OrderServiceTest` lives in `com.example.order` (under `src/test/java`) because it tests `OrderService` which lives in `com.example.order` (under `src/main/java`). This mirroring is a Maven convention because it keeps test classes co-located with their subjects without mixing them into the production source root.

**Step 3: Create source files inside the package**

To create a Java class inside a package:

1. Right-click the `com.example.order` package node **under `src/main/java`** → **New → Java Class**
2. Type the class name (e.g., `OrderItem`) and press **Enter**

IntelliJ creates the file with the correct `package com.example.order;` declaration already in place at the top. You do not need to type the package statement manually.

Repeat this for each class. The final structure will look like:

```
src/
├── main/
│   └── java/
│       └── com/
│           └── example/
│               ├── Main.java
│               └── order/
│                   ├── OrderItem.java
│                   └── OrderService.java
└── test/
    └── java/
        └── com/
            └── example/
                └── order/
                    └── OrderServiceTest.java
```

> **Common mistake:** If you right-click the project root or the `src` folder instead of `src/main/java`, the new package will be created outside the source root and IntelliJ will not recognize it as part of the compilable source tree. Always right-click the blue `src/main/java` folder for production classes and the green `src/test/java` folder for test classes.

### Starter source files

Once the packages exist, populate the files. They contain intentional problems you will fix during the exercises. Do not "correct" them yet. Create each file by right-clicking the appropriate package → **New → Java Class**, then replace the generated stub with the code below.

**`src/main/java/com/example/order/OrderItem.java`**
```java
package com.example.order;

public class OrderItem {
    private String productId;
    private int quantity;
    private double unitPrice;

    public OrderItem(String productId, int quantity, double unitPrice) {
        this.productId = productId;
        this.quantity = quantity;
        this.unitPrice = unitPrice;
    }

    public String getProductId() { return productId; }
    public int getQuantity() { return quantity; }
    public double getUnitPrice() { return unitPrice; }

    public double lineTotal() {
        return quantity * unitPrice;
    }
}
```

**`src/main/java/com/example/order/OrderService.java`**
```java
package com.example.order;

import java.util.ArrayList;
import java.util.List;

public class OrderService {

    // Calculate total for a list of items, optionally applying a premium discount
    public double calculateTotal(List<OrderItem> items, boolean isPremiumCustomer) {
        // Validate
        if (items == null) {
            throw new IllegalArgumentException("Order has no items");
        }
        if (items.isEmpty()) {
            throw new IllegalArgumentException("Order has no items");
        }
        if (items.get(0).getProductId() == null) {
            throw new IllegalArgumentException("Order has no customer");
        }

        // Calculate total
        double total = 0;
        for (int i = 0; i < items.size(); i++) {
            OrderItem item = items.get(i);
            total = total + (item.getQuantity() * item.getUnitPrice());
        }

        // Apply discount
        if (isPremiumCustomer == true) {
            total = total * 0.9;
        }

        // Apply free shipping threshold
        if (total >= 100.0) {
            // No shipping charge
        } else {
            total = total + 9.99;
        }

        return total;
    }

    public List<OrderItem> filterByMinValue(List<OrderItem> items, double minLineTotal) {
        List<OrderItem> result = new ArrayList<>();
        for (OrderItem item : items) {
            if (item.lineTotal() >= minLineTotal) {
                result.add(item);
            }
        }
        return result;
    }
}
```

**`src/test/java/com/example/order/OrderServiceTest.java`**
```java
package com.example.order;

import org.junit.jupiter.api.Test;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;

class OrderServiceTest {

    private final OrderService service = new OrderService();

    @Test
    void standardCustomerTotalWithShipping() {
        var items = List.of(
            new OrderItem("SKU-A", 2, 10.00),  // line total = 20.00
            new OrderItem("SKU-B", 1, 30.00)   // line total = 30.00
        );
        // total = 50.00, below free-shipping threshold → +9.99 shipping
        assertEquals(59.99, service.calculateTotal(items, false), 0.001);
    }

    @Test
    void premiumCustomerGetsDiscount() {
        var items = List.of(
            new OrderItem("SKU-A", 4, 50.00)   // line total = 200.00
        );
        // 200 * 0.9 = 180.00, above shipping threshold
        assertEquals(180.00, service.calculateTotal(items, true), 0.001);
    }

    @Test
    void nullItemsThrowsException() {
        assertThrows(IllegalArgumentException.class,
            () -> service.calculateTotal(null, false));
    }

    @Test
    void filterKeepsOnlyItemsAboveMinValue() {
        var items = List.of(
            new OrderItem("SKU-A", 1, 5.00),   // 5.00 — below threshold
            new OrderItem("SKU-B", 2, 15.00),  // 30.00 — above threshold
            new OrderItem("SKU-C", 3, 10.00)   // 30.00 — above threshold
        );
        var filtered = service.filterByMinValue(items, 20.00);
        assertEquals(2, filtered.size());
    }
}
```

Verify the project compiles: open the **Maven** tool window → **Lifecycle → compile**. Fix any import errors if prompted.

---

## Exercise 1: Project Setup and IDE Orientation

**Estimated time:** 30 minutes  
**Topics covered:** Project Structure, SDK configuration, Maven integration, tool windows, editor basics

### Context

IntelliJ operates on a fully resolved semantic model of your code. Every 
This is why the same action (for example, **Rename**) reliably updates every import, every Javadoc reference, and every Spring configuration file that refers to the renamed symbol. Getting the project model configured correctly is the prerequisite for all of that to work.

### Task 1.1: Verify SDK and Project Structure

1. Open **File → Project Structure** (`Ctrl+Alt+Shift+S`)
2. Under **Project**, confirm that the **SDK** is set to Java 17 and that the **Language level** matches
3. Under **Modules**, expand the `ide-exercises` module and confirm that:
   - `src/main/java` has a **blue** source folder icon (production sources)
   - `src/test/java` has a **green** test source folder icon (test sources)
   - `src/main/resources` has a resources icon

> **Why this matters:** IntelliJ will not discover test classes unless the test source root is marked correctly. In Maven projects this is set automatically on import, but it is important to know where to check when something goes wrong.

### Task 1.2: The Maven Tool Window

Open the **Maven** tool window (View → Tool Windows → Maven, or the Maven icon in the right sidebar).

Explore the following:
- Expand **Lifecycle**: these are the Maven phases you can run directly from the IDE
- Expand **Dependencies**: observe that `junit-jupiter` appears under test scope
- Right-click on `junit-jupiter` → **Show in Diagram**. This displays the full transitive dependency graph. Note that JUnit pulls in `junit-jupiter-api`, `junit-jupiter-params`, etc. automatically

**Task:** Click **Lifecycle → test** in the Maven tool window to run all tests. Confirm all four tests pass. The output appears in the **Run** tool window at the bottom.

### Task 1.3: Essential Editor Keyboard Shortcuts

Work through each shortcut in the table below. Open `OrderService.java` and practice each one. Remember that your key bindings may differ. Use Search Everywhere (Shift-Shift) to find the action if the shortcut does not work.

| Action | Shortcut | What to do |
|---|---|---|
| Reformat code | `Ctrl+Alt+L` | Press inside `OrderService.java`. Observe spacing and brace alignment normalize |
| Optimize imports | `Ctrl+Alt+O` | Remove any unused imports |
| Generate code | `Alt+Insert` | Position cursor inside `OrderItem`, press `Alt+Insert` → explore what can be generated |
| Comment line | `Ctrl+/` | Toggle a line comment on the discount block |
| Duplicate line | `Ctrl+D` | Duplicate a line in `OrderService` then undo with `Ctrl+Z` |
| Multiple cursors | `Alt+Click` | Hold Alt and click on multiple lines to edit them simultaneously |
| Expand/collapse | `Ctrl+-` / `Ctrl+=` | Collapse then expand a method body |

### Task 1.4: The Project Tool Window

1. Press `Alt+1` to open the **Project** tool window
2. Use the **gear icon** in the tool window header to toggle **Compact Middle Packages** on and off. Observe how the package tree changes
3. Right-click the `com.example.order` package → **New → Java Class**. Create a class called `OrderSummary`. Delete it immediately using `Delete` key. Note how IntelliJ asks for confirmation because it is a safe delete that checks for usages

### Checkpoints

1. What is the difference between a **source root** and a **test source root**? What goes wrong if test sources are marked as production sources?
2. Why is reformatting code (`Ctrl+Alt+L`) preferable to manually adjusting spacing?
3. The Maven tool window shows dependency scope. Why does it matter that JUnit is `test` scope rather than `compile` scope?

---

## Exercise 2: Navigation in a Codebase

**Estimated time:** 30–40 minutes  
**Topics covered:** Name-based navigation, structure-based navigation, relationship-based navigation, Find Usages, hierarchy views

### Context

IntelliJ provides three fundamentally different navigation modes, each suited to a different question:

- **Name-based**: _"I know what I'm looking for."_ You know the class or file name.
- **Structure-based**: _"I know where I am and want to explore."_ You're in a class and want to understand its shape
- **Relationship-based**: _"I want to understand how this connects."_ You have a symbol and want to know what depends on it.

A text search can find the string `calculateTotal`, but only IntelliJ's semantic model knows exactly which of those occurrences is a call to *this* method on *this* class, as opposed to a different method with the same name.

### Task 2.1: Name-Based Navigation

Practice each shortcut below. Start from any file. These work globally:

**Go to Class** (`Ctrl+N`):
- Press `Ctrl+N` and type `OrdSer` Observe that IntelliJ's camelCase abbreviation matches `OrderService`
- Type `OrderService#filterByMinValue` Note how adding `#methodName` jumps directly to that method

**Go to File** (`Ctrl+Shift+N`):
- Press `Ctrl+Shift+N` and type `pom` Navigate directly to `pom.xml`
- Type `.yml` This would find any YAML config files if they were in this project.

**Search Everywhere** (`Shift+Shift`) or double-tap Shift
- Type `calculateTotal` Observe results across Classes, Files, Symbols, and Actions tabs
- Switch to the **Actions** tab and type `reformat` This finds the Reformat Code action without using any menu

**Go to Symbol** (`Ctrl+Alt+Shift+N`):
- Type `lineTotal` This searches across all named symbols in all classes

### Task 2.2: Structure-Based Navigation

Open `OrderService.java`.

**File Structure Popup** (`Ctrl+F12`):
- Press `Ctrl+F12` A popup lists all members of the class
- Type `filter` The list immediately narrows to `filterByMinValue`
- Press `Enter` To jump to that method
> Note: If your keymap does not have `Ctrl+F12` assigned to File Structure, use Search Everywhere (Shift-Shift) to find the action by name. Note the keymap binding that is assigned to it in your environment.

**Recent Files / Recent Locations**:
- Navigate between `OrderService.java` and `OrderItem.java` a few times
- Press `Ctrl+E` Observe that Recent Files shows your navigation history in order
- Press `Ctrl+Shift+E` Recent Locations shows the *specific code location* within each file you visited, with a snippet of context. This is more useful than Recent Files when you know *where in the file* you were working

### Task 2.3: Relationship-Based Navigation


**Go to Declaration** (`Ctrl+B`):
- In `OrderServiceTest.java`, click on `OrderService` in the field declaration
- Press `Ctrl+B` jumps to the `OrderService` class declaration
- Click on `calculateTotal` in one of the test methods and press `Ctrl+B` . Uumps to the method body in `OrderService`

**Find Usages** (`Alt+F7`):
- Open `OrderService.java`, place the cursor on the class name `OrderService`
- Press `Alt+F7` the **Find** tool window opens and shows every usage of this class across the project
- Observe the categorization: constructor calls, type references, test usages
- Now place the cursor on the `calculateTotal` method name and press `Alt+F7` to see every call site

> **Rule of thumb:** Before you rename, refactor, or delete any symbol, always run `Alt+F7` first to understand the impact.

**Go to Implementation** (`Ctrl+Alt+B`):
- This shortcut is most useful when working with interfaces. For now, create a quick interface to practise:

```java
// Create this file: src/main/java/com/example/order/PricingStrategy.java
package com.example.order;

public interface PricingStrategy {
    double applyDiscount(double total, boolean isPremium);
}
```

```java
// Create this file: src/main/java/com/example/order/StandardPricingStrategy.java
package com.example.order;

public class StandardPricingStrategy implements PricingStrategy {
    @Override
    public double applyDiscount(double total, boolean isPremium) {
        return isPremium ? total * 0.9 : total;
    }
}
```

- In any file, type `PricingStrategy` and press `Ctrl+Alt+B` 
- IntelliJ jumps to `StandardPricingStrategy` (the concrete implementation). 
- If multiple implementations existed, it would present a list.

**Hierarchy Views**:
- Place the cursor on `PricingStrategy` interface and press `Ctrl+H` 
- The **Type Hierarchy** view shows the full class hierarchy
- Place the cursor on `applyDiscount` in `StandardPricingStrategy` and press `Ctrl+Alt+H` 
- The **Call Hierarchy** shows which methods call `applyDiscount`, and which methods call those callers. 
- This answers: "how does execution reach this code?"

### Checkpoints

1. You are asked to rename the `calculateTotal` method. Before pressing `Shift+F6`, what shortcut do you run first and why?
2. What is the difference between `Ctrl+B` (Go to Declaration) and `Ctrl+Alt+B` (Go to Implementation)?
3. You type `OrdItm` in the Go to Class dialog and no results appear. What might be wrong, and how would you adjust your search?
4. In a production codebase, `Alt+F7` on a commonly-used method shows 87 usages. The **Usages in test code** group shows 0. What does this tell you about the test coverage of that method?

---

## Exercise 3: Code Inspections, Intentions, and Refactoring

**Estimated time:** 40–50 minutes  
**Topics covered:** Inspections, quick-fix intentions (`Alt+Enter`), Rename, Extract Method, Extract Variable, Change Signature, code style

### Context

IntelliJ's inspection engine continuously analyzes your code as you type against a configurable rule set and highlights issues like syntax errors, logic problems, style violations, and potential bugs. 

This uses the same semantic model that is used in navigation

IntelliJ does not scan text, it understands types, scopes, and control flow.

The **intention action** (`Alt+Enter`) is available when you see a yellow or red highlight. Using `Alt+Enter` offers context-aware fixes, from correcting an obvious error to restructuring code into a better form.

Refactoring tools apply safe, compiler-verified structural changes. When you rename a method with `Shift+F6`, IntelliJ updates every call site, every import, every Javadoc reference, and every Spring configuration file that references it by name.

### Task 3.1: Inspections and Alt+Enter

Open `OrderService.java`. IntelliJ will have already flagged several issues. Work through each one:

**Issue 1: Redundant condition:**
The line `if (isPremiumCustomer == true)` compares a boolean to `true` This is redundant.
- Hover over the highlighted code to read the inspection message
- Press `Alt+Enter` → select **Simplify to 'isPremiumCustomer'** and watch the fix apply automatically

**Issue 2:  Traditional for-loop where enhanced for-loop would work:**
The loop `for (int i = 0; i < items.size(); i++)` can be simplified.
- Place your cursor on the `for` keyword
- Press `Alt+Enter` → look for a suggestion to convert to a for-each loop and apply it

**Issue 3: Empty branch:**
The `if (total >= 100.0) { // No shipping charge }` block is an empty `if` branch.
- Press `Alt+Enter` on the highlighted empty block → observe the options. Choose the fix that inverts the condition and removes the empty branch:

```java
// Before (from the lecture's refactoring example pattern):
if (total >= 100.0) {
    // No shipping charge
} else {
    total = total + 9.99;
}

// After applying the inversion:
if (total < 100.0) {
    total = total + 9.99;
}
```

**Issue 4: Magic numbers:**
The values `0.9`, `9.99`, and `100.0` are magic numbers and their meaning is not self-evident.
- Place the cursor on `0.9`
- Press `Alt+Enter` → **Introduce Constant** → name it `PREMIUM_DISCOUNT_RATE`
- Repeat for `9.99` → `STANDARD_SHIPPING_FEE`
- Repeat for `100.0` → `FREE_SHIPPING_THRESHOLD`

The class should now declare these as `static final` constants at the top.

### Task 3.2: Rename Refactoring

The method `filterByMinValue` could be more explanatory. Rename it to `itemsAboveMinLineTotal`:

1. Place the cursor on `filterByMinValue` in `OrderService.java`
2. Press `Shift+F6`
3. Type the new name: `itemsAboveMinLineTotal`
4. Press `Enter`

Open `OrderServiceTest.java` and confirm that the test method that calls `filterByMinValue` has been updated automatically to `itemsAboveMinLineTotal`.

### Task 3.3: Extract Method Refactoring

The `calculateTotal` method does too many things: it validates, computes the subtotal, applies discounts, and adds shipping. This is the exact problem Extract Method is designed to solve.

Open `OrderService.java`. You will extract three helper methods:

**Step 1: Extract the validation block:**
- Select the three `if` validation statements at the top of `calculateTotal` (lines 1–9 of the method body)
- Press `Ctrl+Alt+M` (Extract Method)
- Name the new method `validateItems`
- Click OK

**Step 2: Extract the subtotal calculation:**
- Select the `for` loop that accumulates `total`
- Press `Ctrl+Alt+M`
- Name it `subtotal`
- IntelliJ correctly infers the parameter type (`List<OrderItem>`) and return type (`double`)

**Step 3: Extract the shipping fee calculation:**
- Select the remaining shipping `if` block
- Press `Ctrl+Alt+M`
- Name it `shippingFee`

The result should be a `calculateTotal` method whose body reads like a high-level summary of the algorithm:

```java
public double calculateTotal(List<OrderItem> items, boolean isPremiumCustomer) {
    validateItems(items);
    double total = subtotal(items);
    if (isPremiumCustomer) {
        total *= PREMIUM_DISCOUNT_RATE;
    }
    total += shippingFee(total);
    return total;
}
```

Run the tests (`Ctrl+Shift+F10` inside the test class). All four should still pass.

### Task 3.4: Extract Variable

Open the `itemsAboveMinLineTotal` method. The condition `item.lineTotal() >= minLineTotal` is clear as-is, but practice the Extract Variable shortcut anyway, which is often useful for complex expressions:

- Select `item.lineTotal()` in the condition
- Press `Ctrl+Alt+V`
- Name the variable `lineTotal`

The loop body should now read:

```java
for (OrderItem item : items) {
    double lineTotal = item.lineTotal();
    if (lineTotal >= minLineTotal) {
        result.add(item);
    }
}
```

> Even when the original expression is not complex, making it a named variable can make the intent of the `if` condition immediately readable.

### Task 3.5:  Change Signature

Add a `String note` parameter to `calculateTotal` to allow a note to be attached to the calculation (even if it is not yet used, this simulates a real-world signature change):

1. Place cursor on the `calculateTotal` method name
2. Press `Ctrl+F6` (Change Signature)
3. Click `+` to add a new parameter
4. Set type to `String`, name to `note`, default value to `null`
5. Click **Refactor**

Check `OrderServiceTest.java`. All call sites have been updated with the `null` default. The tests should still compile and pass.

### Checkpoints

1. What is the difference between an **inspection** and an **intention**? Give an example of each.
2. Why is IntelliJ's **Rename** (`Shift+F6`) safer than a global Find-and-Replace for renaming a method?
3. After the Extract Method refactoring, `calculateTotal` delegates to three private methods. How has this changed the testability of the class?
4. When would you use **Extract Method** vs **Extract Variable**? What problem does each one solve?

---

## Exercise 4: Run Configurations and Debugging

**Estimated time:** 35–45 minutes  
**Topics covered:** Run Configurations (lifecycle states, types, sharing), breakpoints, stepping controls, the Debug tool window, watches, Evaluate Expression, conditional breakpoints

### Context

Every execution in IntelliJ uses a **Run Configuration**: a named, saved blueprint that specifies what to launch, how to launch it, and with what environment. 

Run configurations are the mechanism by which a team shares a consistent launch setup. A shared configuration committed to `.idea/runConfigurations/` means every developer who clones the repository gets the same active profile, environment variables, and JVM arguments.

### Task 4.1: Create and Examine a Run Configuration

**Create a run configuration for the test suite:**

1. In `OrderServiceTest.java`, right-click the class name in the gutter → **Run 'OrderServiceTest'**
   - A **temporary** configuration is created automatically and appears in the run toolbar at the top
2. Open **Run → Edit Configurations** (`Alt+Shift+F10`, then `0`)
3. Find the `OrderServiceTest` configuration under **JUnit**
4. Click the **Store as project file** checkbox. This converts it from temporary to **shared** (stored in `.idea/runConfigurations/`)
5. Click **OK**

**Create a run configuration for the main class:**

1. Create a simple main class to give the configuration something to run:

```java
// src/main/java/com/example/Main.java
package com.example;

import com.example.order.OrderItem;
import com.example.order.OrderService;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        var service = new OrderService();
        var items = List.of(
            new OrderItem("SKU-A", 3, 25.00),
            new OrderItem("SKU-B", 1, 9.99)
        );
        double total = service.calculateTotal(items, false, null);
        System.out.println("Order total: $" + total);
    }
}
```

2. Click the green play icon in the gutter next to `main()` to run it
3. Open **Edit Configurations** again and examine the `Main` configuration:
   - Note the **VM options** field. This is where you would set `-Xmx2g` or `-Dspring.profiles.active=dev`
   - Note the **Environment variables** field. This is where secrets are injected without appearing in log output

### Task 4.2: Basic Debugging: Breakpoints and Stepping

In this part, you will trace the execution of `calculateTotal` 

**Set a line breakpoint:**
1. Open `OrderService.java`
2. Click in the **left gutter** on the line `double total = subtotal(items);` and a red circle appears
3. Switch the toolbar from **Run** to **Debug** (the bug icon) and launch `Main` in debug mode: **Run → Debug 'Main'** or `Shift+F9`

Execution pauses at the breakpoint. The **Debug tool window** opens at the bottom with four key panels:
- **Frames** (left): the current call stack. Click any frame to inspect variables at that level
- **Variables** (right): all local variables and fields in scope at the current frame
- **Console**: stdout/stderr output
- **Evaluate** bar: type any expression to evaluate it live

**Step through the code:**

Use the stepping controls:

| Action | Shortcut | When to use |
|---|---|---|
| Step Over | `F8` | Execute the current line without entering any method calls |
| Step Into | `F7` | Enter the method being called on the current line |
| Step Out | `Shift+F8` | Finish the current method and return to the caller |
| Run to Cursor | `Alt+F9` | Run until the line where the cursor is, then pause |
| Resume | `F9` | Continue until the next breakpoint |

Practice:
1. Press `F8` (Step Over) once. The line executes and `total` appears in the Variables panel with its computed value. Observe the **inline value** shown in grey text directly on the source line.
2. Place the cursor on the closing `return total;` line
3. Press `Alt+F9` (Run to Cursor). Execution jumps to that line
4. Inspect the `total` variable in the Variables panel. Confirm it matches the expected output

### Task 4.3: Navigating the Call Stack

1. Restart the debug session (`Ctrl+F5`)
2. When execution pauses at the breakpoint, press `F7` (Step Into) to enter the `subtotal` method
3. In the **Frames** panel, click the `calculateTotal` frame above `subtotal`
4. Observe that the Variables panel updates to show the state of `calculateTotal`'s local variables: the `items` list and `isPremiumCustomer` flag

With the call stack navigator you can inspect the full context of every method in the call chain without re-running anything.

### Task 4.4: Watches and Evaluate Expression

While paused in the `subtotal` method:

**Add a watch:**
1. In the Watches area (top-right of the Variables panel), click `+`
2. Type: `items.size()` → press Enter
3. The watch expression is continuously evaluated and displayed as you step

**Evaluate Expression** (`Alt+F8`):
1. Press `Alt+F8` to open the Evaluate Expression dialog
2. Type: `items.stream().mapToDouble(i -> i.getQuantity() * i.getUnitPrice()).sum()`
3. Press **Evaluate** and the result appears immediately. This lets you test arbitrary expressions against the live runtime state without modifying code.

### Task 4.5: Conditional Breakpoints

A conditional breakpoint only pauses execution when a boolean expression is true. This is essential when debugging a loop because you do not want to stop on every iteration when the problem only occurs for specific data.

1. Open `OrderService.java`, locate the `itemsAboveMinLineTotal` method
2. Right-click the red breakpoint circle on the `if (lineTotal >= minLineTotal)` line
3. In the breakpoint settings popup, enter the condition: `lineTotal > 25.0`
4. Click **Done**

Now add a test call to `Main.main()`:

```java
var filtered = service.itemsAboveMinLineTotal(items, 20.0);
System.out.println("Items above threshold: " + filtered.size());
```

Run in debug mode. The debugger only pauses inside the loop when `lineTotal > 25.0`  It steps silently past the `9.99` item.

### Task 4.6: Logging Breakpoints (Non-Suspending)

A logging breakpoint prints a message without halting execution. This is  effectively a zero-code `System.out.println` that you attach and detach at runtime without modifying source files.

1. Right-click the breakpoint on the `shippingFee` line (or add one)
2. Uncheck **Suspend**
3. Enable **Evaluate and log**
4. Enter: `"shippingFee called with total=" + total`
5. Click **Done**

Run in **debug mode** (`Shift+F9`). Observe the log message appearing in the **Debug Console** without the program pausing at that line. The key distinction from a regular breakpoint is that execution continues uninterrupted, but the debugger must still be attached for the expression to be evaluated and logged.

### Checkpoints

1. What are the three lifecycle states of a Run Configuration? Which one should be used for team projects, and why?
2. What is the difference between **Step Over** (`F8`) and **Step Into** (`F7`)? Give a scenario where you would deliberately choose each one.
3. You are debugging a loop that processes 500 items. The bug only affects items with a negative `quantity`. How would you configure a breakpoint to pause only on those items?
4. How is a logging breakpoint different from adding `System.out.println` directly in the code? When is the logging breakpoint approach preferable?

---

## Exercise 5: Running and Managing Tests

**Estimated time:** 30 minutes  
**Topics covered:** Test discovery, running individual tests and suites, the Test Results panel, debugging tests, test coverage

### Context

IntelliJ's test runner is integrated directly with JUnit 5 (and JUnit 4, TestNG). Tests are discovered automatically from the test source root. They require no registration, no XML configuration. 

### Task 5.1: Running Tests at Different Granularities

Open `OrderServiceTest.java` and practice running at each level:

| Level | How to run |
|---|---|
| Single test method | Click the green play icon in the **gutter** next to `@Test` on `standardCustomerTotalWithShipping` |
| Single test class | Click the green play icon next to `class OrderServiceTest` |
| All tests in a package | Right-click `com.example.order` in the Project window → **Run Tests** |
| All tests in the module | Right-click `src/test/java` → **Run All Tests** |
| Test at cursor | Place cursor inside any test method → `Ctrl+Shift+F10` |

After running the full class, examine the **Test Results** panel at the bottom:
- Green checkmarks indicate passing tests
- Click any test name to jump to that test method
- The right panel shows the console output for the selected test

### Task 5.2: Introducing and Diagnosing a Failing Test

Temporarily introduce a bug to practice reading test failure output:

```java
// In OrderService.java, change PREMIUM_DISCOUNT_RATE from 0.9 to 0.8 temporarily
private static final double PREMIUM_DISCOUNT_RATE = 0.8; // was 0.9 — intentional bug
```

Run the full test class. One test fails. In the Test Results panel:
- The failing test is highlighted in red
- The expected vs actual values are shown: `expected: <180.0> but was: <160.0>`
- Click the stack trace link to jump to the assertion that failed

Now revert the change (`Ctrl+Z` or restore `0.9`) and confirm all tests pass again.

### Task 5.3: Debugging a Test

Tests can be launched in debug mode exactly like application code:

1. Add a breakpoint inside `premiumCustomerGetsDiscount` in the test itself
2. Right-click the test method name in the gutter → **Debug 'premiumCustomerGetsDiscount'**
3. Execution pauses at the breakpoint and the Debug tool window opens
4. Step into `service.calculateTotal(...)` You are now inside the production code with the test's data as context
5. Inspect the `total` variable at each step to confirm the discount is applied correctly

You can set breakpoints in both test code *and* production code, and the debugger honors all of them. The call stack shows the full chain from the test assertion down through every production method invoked.

### Task 5.4: Test Coverage

1. Right-click `OrderServiceTest` → **Run 'OrderServiceTest' with Coverage**
2. When the run completes, observe:
   - **Editor gutter**: green bars on covered lines, red bars on uncovered lines
   - **Coverage tool window** (opens automatically): class-level and method-level percentages
3. Note which lines are red. Those are execution paths not exercised by the current tests

**Task:** Identify one uncovered path and write a new test to cover it. For example, the path where `items` is not null but *is* empty may not be covered. Write a test:

```java
@Test
void emptyItemsThrowsException() {
    assertThrows(IllegalArgumentException.class,
        () -> service.calculateTotal(List.of(), false, null));
}
```

Re-run with coverage and confirm the coverage percentage improves.

### Checkpoints

1. IntelliJ reports that `src/test/java` does not have the green test source icon; it shows a blue source icon instead. What does this mean and how would you fix it?
2. You run all tests and one turns red. The failure message says `expected: <59.99> but was: <50.0>`. Describe the debugging steps you would take to find the root cause.
3. What is the difference between IntelliJ's built-in coverage and JaCoCo coverage? Which one matches what a CI pipeline typically reports?

---

## Exercise 6: GitHub Copilot Integration

**Estimated time:** 30–40 minutes  
**Topics covered:** Copilot installation, inline suggestions, prompt engineering in code comments, chat interface, validating generated code

### Context

GitHub Copilot is an AI pair programmer that integrates directly into IntelliJ. It operates in two modes: **inline suggestions** that complete code as you type, and an interactive **chat interface** that accepts natural-language prompts. Both modes are useful, but neither produces code that can be accepted without review.

The key professional discipline is treating Copilot as a fast, knowledgeable colleague who sometimes writes subtly wrong code. Everything it produces must be reviewed against: Does it compile? Does it pass the tests? Does it follow the team's style? Is it using the right API, or a deprecated one? Does it introduce a security concern?

### Task 6.1: Verify Copilot is Active

1. Open **File → Settings → Plugins** (or `Ctrl+Alt+S` → Plugins)
2. Confirm the **GitHub Copilot** plugin is installed and enabled
3. In the bottom-right status bar, look for the Copilot icon. A green icon means it is connected and active; a grey icon means it is disabled or not authenticated

If not yet authenticated:
- Click the Copilot icon → **Login to GitHub** → follow the browser authentication flow

### Task 6: Inline Suggestions: Accepting, Cycling, and Dismissing

Create a new file `src/main/java/com/example/order/DiscountCalculator.java`:

```java
package com.example.order;

public class DiscountCalculator {

    // Calculate loyalty discount based on years of membership
    // 0-1 years: 0%, 2-3 years: 5%, 4-6 years: 10%, 7+ years: 15%
    public double loyaltyDiscount(int yearsOfMembership) {
        // Start typing here and observe Copilot's suggestion
    }
}
```

After the comment, begin typing `return` Copilot will offer a completion. Key controls:

| Action | Key |
|---|---|
| Accept the entire suggestion | `Tab` |
| Accept the next word only | `Ctrl+→` |
| See the next suggestion | `Alt+]` |
| See the previous suggestion | `Alt+[` |
| Dismiss the suggestion | `Escape` |

Cycle through several suggestions using `Alt+]` before accepting. Note that different suggestions may use `if/else` chains, a `switch` expression, or a lookup table. Choose whichever matches the switch expression style introduced in Module 1.

**Validate the accepted code:**
- Read it carefully. Does it handle all four tiers correctly?
- Write a JUnit 5 test in `src/test/java/com/example/order/DiscountCalculatorTest.java` that tests each boundary (0 years, 1 year, 2 years, 4 years, 7 years)
- Run the test. If it fails, correct the generated code manually

### Task 6.3: Prompt Engineering with Comments

Copilot uses the surrounding code and comments as its prompt. Well-placed comments produce significantly better suggestions. Experiment with writing a precise comment *before* the method, then let Copilot complete the method signature and body:

Add to `DiscountCalculator.java`:

```java
    /**
     * Calculates the final price after applying both a loyalty discount
     * and a volume discount. The volume discount applies when quantity >= 10
     * and is 8%. Discounts are additive, not compounded.
     * Returns a value rounded to 2 decimal places.
     */
    public double finalPrice(double unitPrice, int quantity, int yearsOfMembership) {
        // Let Copilot suggest the body
    }
```

Accept or refine the suggestion. Key prompt engineering principles demonstrated here:
- Specify the *exact business rule* (`additive, not compounded`)
- Specify the *output format* (`rounded to 2 decimal places`)
- Specify *parameter types and semantics* in both the Javadoc and the method signature

Write at least two test cases to verify the output, then compare the tested behavior against what the comment specified. Correct any mismatches.

### Task 6.4: Copilot Chat

Open the Copilot Chat panel (View → Tool Windows → GitHub Copilot Chat, or the chat icon in the left sidebar).

**Task A: Explain existing code:**
Paste the `calculateTotal` method into the chat and ask:
> "Explain what this method does and identify any potential issues with the current implementation."

Read the response critically. Does it identify the magic number issue that was already fixed? Does it mention anything about thread safety or null handling?

**Task B: Generate a test:**
Paste the `loyaltyDiscount` method into the chat and ask:
> "Generate a complete JUnit 5 test class for this method covering all boundary conditions and edge cases."

Copy the generated test into `DiscountCalculatorTest.java` and run it. Note any failures. Fix either the test or the implementation as appropriate, but do not blindly accept either.

**Task C: Ask for a refactoring:**
Paste the `itemsAboveMinLineTotal` method from `OrderService.java` and ask:
> "Rewrite this method using the Java Streams API instead of a for loop."

Compare the suggested stream version with your own from Module 1 Exercise 3. Accept the version you believe is clearer and more correct.

### Task 6.5: Identifying and Correcting Problematic Suggestions

Copilot sometimes suggests code that compiles but is subtly wrong. This task trains you to catch those cases.

Add the following comment and let Copilot complete the method. Do **not** edit the comment. Accept the first suggestion Copilot offers:

```java
    // Returns true if the order total exceeds the free shipping threshold
    public boolean qualifiesForFreeShipping(double orderTotal) {
        // Accept Copilot's suggestion without reading it first
    }
```

Now answer these questions by inspecting the suggestion:
1. Did Copilot use the right constant (`FREE_SHIPPING_THRESHOLD` from `OrderService`)? Or did it hardcode `100.0`?
2. Is the comparison `>` (strictly greater) or `>=` (greater or equal)? Does that match the business rule in `OrderService`?
3. Write a test that catches any discrepancy and run it

The lesson: Copilot does not have access to your domain's specific business rules unless you give it context. The generated code may be *plausible* without being *correct*.

### Checkpoints

1. Copilot suggests a method implementation that compiles and the tests pass. Is that sufficient to accept it? What else would you check?
2. What is the relationship between the quality of your comments and the quality of Copilot's suggestions?
3. Name two scenarios where using Copilot is clearly beneficial, and one scenario where you would be more cautious about accepting its output.
4. A Copilot suggestion uses `java.util.Date` to handle a timestamp. You know `Date` is deprecated in favor of `java.time.LocalDateTime`. What does this tell you about Copilot's knowledge, and how do you handle it?

---

## Summary and Reflection

After completing all six exercises, you have covered every topic in Module 0:

| Exercise | Topics | Key Takeaway |
|---|---|---|
| 1 | Project setup, SDK, Maven, editor basics | The project model must be correct for all IDE tools to work reliably |
| 2 | Navigation (name, structure, relationship) | `Alt+F7` before you change anything; `Ctrl+B` to understand what you're reading |
| 3 | Inspections, intentions, refactoring | `Alt+Enter` is the most productive key in IntelliJ; refactoring tools are safer than find-and-replace |
| 4 | Run Configurations, debugging | Shared configurations are team hygiene; the debugger gives you more information than reading code |
| 5 | Test running, coverage | Tests run at multiple granularities; coverage shows what your tests don't exercise |
| 6 | Copilot: suggestions, chat, validation | Copilot accelerates generation; you are responsible for correctness |

### Final Reflection Questions

1. You are joining a new team's Java project. What is the first thing you do in IntelliJ to orient yourself in the codebase, and why?

2. A colleague says "I don't need the debugger. I just add `System.out.println` everywhere." What would you say to them, and what specific debugger capabilities would you demonstrate?

3. Your team lead asks you to rename a public interface method that has been in production for two years. Walk through the exact steps you would take in IntelliJ to do this safely.

4. You ask Copilot to generate a method that processes sensitive data. The generated code is functional. What specific concerns would you review before accepting it?

---

## Quick Reference: IntelliJ Keyboard Shortcuts
- Remember that your specific keymap may differ. Use **Search Everywhere** (Shift-Shift) to find any action by name and see its assigned shortcut in your environment.

### Navigation
| Action | Shortcut |
|---|---|
| Go to Class | `Ctrl+N` |
| Go to File | `Ctrl+Shift+N` |
| Search Everywhere | `Shift+Shift` |
| Go to Symbol | `Ctrl+Alt+Shift+N` |
| Go to Declaration | `Ctrl+B` |
| Go to Implementation | `Ctrl+Alt+B` |
| Find Usages | `Alt+F7` |
| File Structure Popup | `Ctrl+F12` |
| Recent Files | `Ctrl+E` |
| Recent Locations | `Ctrl+Shift+E` |
| Type Hierarchy | `Ctrl+H` |
| Call Hierarchy | `Ctrl+Alt+H` |

### Editing & Refactoring
| Action | Shortcut |
|---|---|
| Intention Actions | `Alt+Enter` |
| Rename | `Shift+F6` |
| Extract Method | `Ctrl+Alt+M` |
| Extract Variable | `Ctrl+Alt+V` |
| Extract Constant | `Ctrl+Alt+C` |
| Change Signature | `Ctrl+F6` |
| Move Class | `F6` |
| Reformat Code | `Ctrl+Alt+L` |
| Optimize Imports | `Ctrl+Alt+O` |
| Generate Code | `Alt+Insert` |
| Duplicate Line | `Ctrl+D` |
| Comment Line | `Ctrl+/` |

### Debugging
| Action | Shortcut |
|---|---|
| Debug | `Shift+F9` |
| Step Over | `F8` |
| Step Into | `F7` |
| Force Step Into | `Alt+Shift+F7` |
| Step Out | `Shift+F8` |
| Run to Cursor | `Alt+F9` |
| Resume | `F9` |
| Evaluate Expression | `Alt+F8` |

### Testing
| Action | Shortcut |
|---|---|
| Run test at cursor | `Ctrl+Shift+F10` |
| Re-run last test | `Shift+F10` |
| Run with Coverage | Right-click → Run with Coverage |

### Copilot
| Action | Shortcut |
|---|---|
| Accept suggestion | `Tab` |
| Accept next word | `Ctrl+→` |
| Next suggestion | `Alt+]` |
| Previous suggestion | `Alt+[` |
| Dismiss | `Escape` |

---

*End of Module 0 Exercises*
