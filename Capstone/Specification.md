# Capstone Specification

#### Version 3.0 July 29

## Introduction and Background

The Bank had originally commissioned a React SPA client for the use of both account holders and front line bank staff. 

The original React SPA application implemented security using the native React libraries. The application was shelved because it failed the Bank's security review to ensure regulatory compliance with oversight agencies.

There is currently interest in reactivating the original project but using the OAuth recommendation for delegating the security to a BFF, backend for frontend, component.

Your project is a proof of concept project to confirm whether the BFF architecture is a viable approach solving the security issue.

---

## Environment 


Since this is a proof of concept project, your team will have to work in development environment with mocks of the main productions components that the SPA/BFF will have to interact with.

You have seen all the environment pieces in the labs. The architecture looks like this

```
   SPA  ──►  BFF  ──►  bankapi  ──►  Oracle
  :5173    :8080      :8081     ├─►  Kafka
                                └─►  payment mock
     login │                         :8090
           ▼
       authserver  ◄── bankapi and BFF validate tokens against this issuer
        :9000
```

### Authentication Server

You will need to run a mock authentication server. You already have done most of this in the labs. There are only a few small changes necessary to make it usable in the project.

Since this is part of the scaffolding, there is a Spring Boot project you can build in AuthServer directory to get the correctly configured authentication server up and running.


### WireMock Server

You will need a wire mock server to emulate an external payment service. You have already written the code for it in one of the labs as part of the BankAPI. All that will be required is to extract the wiremock code into a stand alone Spring Boot project

Since this is part of the scaffolding you have already done, there is a Spring Boot project specification in the Wiremock directory that you can use to get it up and running.

### Kafka Broker and Oracle Database

You will be provided with a DDL for an Oracle database for persistent storage for transactions. You can use Docker to run the database. The work you will be required to do will be similar to what you did in the labs.

Similarly, you will be provided with a message schema for using a Kafka topic. You can also use Docker for Kafka. As with Oracle, the work you will be required to do will be similar to what you did in the labs.

These are located in the supplemental capstone documents.

### BankService

This will be a mockup of the actual bank service. This will be based on the BankAPI project you created in the labs.

Using the lab version, you will be required to integrate the database connectivity and the Kafka connectivity, as well as implementing all the required security constraints.

### React SPA

You can use the last version of the SPA from Lab 4-8 as representing the legacy project you are upgrading. There are some modifications necessary to add the new operations as specified in the SPA supplement.

---

## Tasking

While there is work required get the mock components working, most of your work will take place in three components.

### React SPA

The main task will be to run the React functionality through the BFF in a provably secure manner.

However, not all the functionality required is in the SPA, you will have to add some additional capability, such as the facility for the teller to make deposits and withdrawals and to make payments.

### BFF

This the key component since it connects the SPA to the bank infrastructure, or at least the mocks you have created.

This component did not exist in the original project. You will have to create the BFF and link it to the SPA application.

You can use the BFF from Lab 4-8 as the starting point. However, you will have to make some changes in several places so that it works with the new security rules and API contract.

---

## SPA Overview

The SPA is designed to be deployed into a bank web application. There are two different types of users

### Functional Overview

There are two types of users

1. Customers
   - These are account holders. 
   - They can query their accounts, review transactions on their accounts and make transfers between accounts.
   - Customers can only see their own accounts can only change the account balance by executing transfers.
   - The application supports two kinds of transfers.
     - Internal transfers between a single customer's accounts
     - External transfers between the customer and an external payment service (for utility payments for example).

2. Tellers
   - Tellers can view any customer's accounts. 
   - The can also make transfers between a specific customer's accounts but not between accounts that belong to different customers.
   - Tellers can also record deposits and withdrawals on an account in order to record cash transactions done by a teller at the bank.

The original application only supported the Customer functionality, you will have to add the Bank Staff functionality

#### Business Rules
- There a set of business rules that have to be implemented by the capstone. 
- These are provided in a supplemental document.

---

## BankService

The BanksService needs to implement the following features

### System of Record

An Oracle database represents the system of record for the bank application.

For this project, the data model has three entities
1. Users - Customers and bank employees. For this project, the customer records are read only
2. Accounts - Represent bank accounts. The only operations allowed are updates to the balance
3. Transactions - The main table that tracks all executed transactions


### Audit

Every transaction, including failed transactions, must be recorded in an audit table in the database. The data model for the audit table will be provided in a separate data specification.

The audit table entries should be automatic and use an Oracle audit trigger to entries are automatically committed.

### External Transfers

In addition to transfers between accounts, the user can do a transfer to an external payment service.

This external service will be mocked up with your WireMock application. The specific endpoints required will be supplied in an external service specification.

When the external service responds with success, the debit the account is debited and the amount recorded as a single TRANSFER_OUT transaction with status COMPLETED. On failure, a FAILED transaction is recorded, but the account is not debited

This is returned to the SPA client as 502 HTTP code.

### Statistics Collector

Each transaction is anonymized and written to a Kafka topic. The format of the message will be provided separately.  

As an extension, you can add in a Kafka consumer that writes the contents of the topic to a CSV file

### Security

The security should be implemented at both the endpoints and in the service layer for enforcement of business rules.

A full list of endpoints is provided in the API contract supplement document.

The database operations must also be authorized at the service layer of the application.

---

## BFF

The BFF component must perform the passthrough requests from the SPA to the BankService correctly. 

One critical requirement for the BFF is that it handes token invalidation on logout from the SPA, which was covered in Lab 4-8

---

## Testing and Validation

Part of the deliverables is a full set of functional tests, both unit and integration tests, that validate the correctness of your work.

The presentation will require you to demonstrate the flow a transaction takes from end to end through your project

There is a set of business rules provided in a supplemental document that.

---

## Bonus

The following are not required but are additional pieces you can try to exercise your creativity. 

Even if you don't get working code implemented for these bonus features, come up with a design and prepare a brief overview on how you design and implement these features

### Security Log

The BFF records all 401 and 403 errors in a Kafka security topic.

### Transaction report

The BankService has a table that records statistics about transactions. This contains a count and total amount for each type of transaction. 

As each transaction is recorded, the corresponding fields in the transaction report are updated.

The report is available to bank employees through a Report endpoint, but does not have to be accessible from the SPA


### Resilience

- Implement the retry or circuit resilience pattern and demonstrate that it works. 

### Account Metadata

The bank accounts each have a status code which is either ACTIVE or INACTIVE which is fixed for the project. For a challenge, implement an endpoint that allows a bank employee to change the status using a PUT method.


## End
