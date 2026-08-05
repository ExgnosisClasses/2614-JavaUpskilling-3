ALTER SESSION SET CONTAINER = XEPDB1;
CONNECT labuser/labpass123@localhost/XEPDB1
-- Customers
INSERT INTO customers (customer_number, full_name, email)
  VALUES ('487-978493', 'Alice Customer', 'alice@example.com');
INSERT INTO customers (customer_number, full_name, email)
  VALUES ('500-100200', 'Bob Customer', 'bob@example.com');

-- Accounts: all ACTIVE except one INACTIVE for Alice.
-- customer_id is resolved by customer_number so we never assume identity values.
INSERT INTO accounts (account_number, customer_id, account_type, account_status, balance)
  VALUES ('128-9878-001',
          (SELECT customer_id FROM customers WHERE customer_number = '487-978493'),
          'CHECKING', 'ACTIVE', 5000.00);
INSERT INTO accounts (account_number, customer_id, account_type, account_status, balance)
  VALUES ('128-9878-002',
          (SELECT customer_id FROM customers WHERE customer_number = '487-978493'),
          'SAVINGS', 'ACTIVE', 10000.00);
INSERT INTO accounts (account_number, customer_id, account_type, account_status, balance)
  VALUES ('128-9878-003',
          (SELECT customer_id FROM customers WHERE customer_number = '487-978493'),
          'CHECKING', 'INACTIVE', 0.00);
INSERT INTO accounts (account_number, customer_id, account_type, account_status, balance)
  VALUES ('128-9878-004',
          (SELECT customer_id FROM customers WHERE customer_number = '500-100200'),
          'CHECKING', 'ACTIVE', 2500.00);
COMMIT;