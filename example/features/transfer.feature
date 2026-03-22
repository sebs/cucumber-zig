Feature: Money Transfers
  As a bank customer
  I want to transfer money between accounts
  So that I can pay other people

  Scenario: Transfer between two accounts
    Given a new account for "Alice"
    And a new account for "Bob"
    And "Alice" has a balance of 1000
    When "Alice" transfers 300 to "Bob"
    Then "Alice" should have a balance of 700
    And "Bob" should have a balance of 300

  Scenario: Transfer fails with insufficient funds
    Given a new account for "Alice"
    And a new account for "Bob"
    And "Alice" has a balance of 100
    When "Alice" tries to transfer 500 to "Bob"
    Then the transfer should be declined
    And "Alice" should have a balance of 100
    And "Bob" should have a balance of 0

  @smoke
  Scenario: Transfer entire balance
    Given a new account for "Alice"
    And a new account for "Bob"
    And "Alice" has a balance of 500
    When "Alice" transfers 500 to "Bob"
    Then "Alice" should have a balance of 0
    And "Bob" should have a balance of 500
