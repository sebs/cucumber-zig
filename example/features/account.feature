Feature: Bank Account Management
  As a bank customer
  I want to manage my account
  So that I can track my finances

  Background:
    Given a new account for "Alice"

  Scenario: Initial balance is zero
    Then the balance should be 0

  Scenario: Depositing money
    When I deposit 100
    Then the balance should be 100

  Scenario: Withdrawing money
    Given I deposit 500
    When I withdraw 200
    Then the balance should be 300

  Scenario: Cannot withdraw more than balance
    Given I deposit 100
    When I try to withdraw 200
    Then the withdrawal should be declined
    And the balance should be 100

  @smoke
  Scenario: Multiple deposits
    When I deposit 100
    And I deposit 250
    And I deposit 50
    Then the balance should be 400

  Scenario Outline: Deposit various amounts
    When I deposit <amount>
    Then the balance should be <amount>

    Examples:
      | amount |
      | 50     |
      | 100    |
      | 999    |
