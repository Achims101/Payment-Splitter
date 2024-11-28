# Split Payment Smart Contract

A Clarity smart contract for the Stacks blockchain that enables automated payment distribution among multiple recipients with configurable shares.

## About

This smart contract allows for automated distribution of fungible tokens to multiple recipients based on predefined share percentages. It's ideal for use cases such as:
- Revenue sharing
- Royalty distributions
- Team payment allocations
- Automated payment splits
- Dividend distributions

## Features

- Support for any SIP-010 compliant fungible token
- Configurable recipient shares
- Dynamic recipient management
- Automated payment distribution
- Recipient status toggling (active/inactive)
- Share percentage validation
- Comprehensive error handling

## Contract Interface

### Administrative Functions

1. `register-recipient`
   - Adds a new payment recipient
   - Parameters:
     - `recipient-address`: Principal
     - `share-percentage`: uint (0-10000)

2. `unregister-recipient`
   - Removes an existing recipient
   - Parameters:
     - `recipient-address`: Principal

3. `modify-recipient-share`
   - Updates a recipient's share percentage
   - Parameters:
     - `recipient-address`: Principal
     - `updated-share-percentage`: uint (0-10000)

4. `toggle-recipient-status`
   - Enables/disables a recipient
   - Parameters:
     - `recipient-address`: Principal

### Payment Functions

1. `process-payment-distribution`
   - Distributes payment among active recipients
   - Parameters:
     - `token-contract`: FungibleToken
     - `total-payment-amount`: uint

### Read-Only Functions

1. `get-recipient-details`
   - Returns recipient information
   - Parameters:
     - `recipient-address`: Principal

2. `get-cumulative-shares`
   - Returns total allocated shares

3. `is-contract-admin`
   - Checks if an address is the contract administrator
   - Parameters:
     - `account-address`: Principal

## Error Codes

- `ERR-UNAUTHORIZED-ACCESS (u100)`: Caller isn't authorized
- `ERR-RECIPIENT-NOT-FOUND (u101)`: Recipient doesn't exist
- `ERR-INVALID-SHARE-AMOUNT (u102)`: Share percentage is invalid
- `ERR-DUPLICATE-RECIPIENT (u103)`: Recipient already exists
- `ERR-NO-ACTIVE-RECIPIENTS (u104)`: No active recipients found
- `ERR-TOTAL-SHARES-EXCEEDED (u105)`: Total shares exceed 100%
- `ERR-INSUFFICIENT-TOKEN-BALANCE (u106)`: Insufficient token balance

## Usage Example

```clarity
;; Register a recipient with 30% share
(contract-call? .split-payment register-recipient 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u3000)

;; Distribute 1000 tokens
(contract-call? .split-payment process-payment-distribution .token-contract u1000)
```

## Security Considerations

1. Only the contract administrator can modify recipient information
2. Share percentages are validated to prevent exceeding 100%
3. Balance checks are performed before distributions
4. Active/inactive status prevents accidental payments
5. All operations are atomic and revert on failure

## Best Practices

1. Keep total shares at 100% (10000 basis points)
2. Verify recipient addresses before registration
3. Test distribution with small amounts first
4. Monitor active/inactive status of recipients
5. Maintain accurate records of share modifications