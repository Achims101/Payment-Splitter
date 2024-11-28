;; Split Payment Smart Contract
;; Allows splitting payments between multiple recipients with configurable shares

(use-trait fungible-token .sip-010-trait-ft.sip-010-trait)

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-RECIPIENT-NOT-FOUND (err u101))
(define-constant ERR-INVALID-SHARE-AMOUNT (err u102))
(define-constant ERR-DUPLICATE-RECIPIENT (err u103))
(define-constant ERR-NO-ACTIVE-RECIPIENTS (err u104))
(define-constant ERR-TOTAL-SHARES-EXCEEDED (err u105))
(define-constant ERR-INSUFFICIENT-TOKEN-BALANCE (err u106))

;; Data variables
(define-data-var contract-administrator principal tx-sender)
(define-map payment-recipients 
    principal 
    { share-percentage: uint, is-active: bool })
(define-data-var cumulative-shares uint u0)
(define-data-var recipient-list (list 100 principal) (list))

;; Read-only functions
(define-read-only (get-recipient-details (recipient-address principal))
    (default-to 
        { share-percentage: u0, is-active: false }
        (map-get? payment-recipients recipient-address))
)

(define-read-only (get-cumulative-shares)
    (var-get cumulative-shares)
)

(define-read-only (get-recipient-list)
    (var-get recipient-list)
)

(define-read-only (is-contract-admin (account-address principal))
    (is-eq account-address (var-get contract-administrator))
)

;; Private functions
(define-private (calculate-payment-share (total-payment-amount uint) (recipient-share-percentage uint))
    (/ (* total-payment-amount recipient-share-percentage) (var-get cumulative-shares))
)

(define-private (execute-token-transfer 
    (token-contract <fungible-token>) 
    (recipient-address principal) 
    (transfer-amount uint)
)
    (contract-call? 
        token-contract 
        transfer 
        transfer-amount 
        tx-sender 
        recipient-address 
        none
    )
)

;; Public functions
(define-public (register-recipient (recipient-address principal) (share-percentage uint))
    (begin
        (asserts! (is-contract-admin tx-sender) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> share-percentage u0) ERR-INVALID-SHARE-AMOUNT)
        (asserts! 
            (is-none (map-get? payment-recipients recipient-address))
            ERR-DUPLICATE-RECIPIENT
        )
        
        (let ((updated-total-shares (+ (var-get cumulative-shares) share-percentage)))
            (asserts! (<= updated-total-shares u10000) ERR-TOTAL-SHARES-EXCEEDED)
            
            (map-set payment-recipients 
                recipient-address 
                { share-percentage: share-percentage, is-active: true }
            )
            (var-set cumulative-shares updated-total-shares)
            (var-set recipient-list (unwrap! (as-max-len? (append (var-get recipient-list) recipient-address) u100) ERR-TOTAL-SHARES-EXCEEDED))
            (ok true)
        )
    )
)

(define-public (unregister-recipient (recipient-address principal))
    (begin
        ;; First check authorization
        (asserts! (is-contract-admin tx-sender) ERR-UNAUTHORIZED-ACCESS)
        
        ;; Then check if recipient exists and handle accordingly
        (let ((recipient-record (map-get? payment-recipients recipient-address)))
            (asserts! (is-some recipient-record) ERR-RECIPIENT-NOT-FOUND)
            
            ;; If we get here, we know recipient exists, so we can safely unwrap
            (let ((record (unwrap! recipient-record ERR-RECIPIENT-NOT-FOUND)))
                (var-set cumulative-shares 
                    (- (var-get cumulative-shares) 
                       (get share-percentage record)))
                (map-delete payment-recipients recipient-address)
                (var-set recipient-list 
                    (filter not-this-recipient (var-get recipient-list)))
                (ok true)
            )
        )
    )
)

(define-private (not-this-recipient (address principal))
    (not (is-eq address tx-sender))
)

(define-public (modify-recipient-share (recipient-address principal) (updated-share-percentage uint))
    (begin
        (asserts! (is-contract-admin tx-sender) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> updated-share-percentage u0) ERR-INVALID-SHARE-AMOUNT)
        
        (let ((recipient-record (map-get? payment-recipients recipient-address)))
            (asserts! (is-some recipient-record) ERR-RECIPIENT-NOT-FOUND)
            
            (let ((record (unwrap! recipient-record ERR-RECIPIENT-NOT-FOUND)))
                (let (
                    (current-share (get share-percentage record))
                    (new-total-shares (+ (- (var-get cumulative-shares) current-share) updated-share-percentage))
                )
                    (asserts! (<= new-total-shares u10000) ERR-TOTAL-SHARES-EXCEEDED)
                    (map-set payment-recipients 
                        recipient-address 
                        { 
                            share-percentage: updated-share-percentage, 
                            is-active: (get is-active record) 
                        }
                    )
                    (var-set cumulative-shares new-total-shares)
                    (ok true)
                )
            )
        )
    )
)

(define-public (toggle-recipient-status (recipient-address principal))
    (begin
        (asserts! (is-contract-admin tx-sender) ERR-UNAUTHORIZED-ACCESS)
        
        (let ((recipient-record (map-get? payment-recipients recipient-address)))
            (asserts! (is-some recipient-record) ERR-RECIPIENT-NOT-FOUND)
            
            (let ((record (unwrap! recipient-record ERR-RECIPIENT-NOT-FOUND)))
                (map-set payment-recipients 
                    recipient-address 
                    { 
                        share-percentage: (get share-percentage record), 
                        is-active: (not (get is-active record)) 
                    }
                )
                (ok true)
            )
        )
    )
)

(define-public (process-payment-distribution (token-contract <fungible-token>) (total-payment-amount uint))
    (begin
        (asserts! (> (var-get cumulative-shares) u0) ERR-NO-ACTIVE-RECIPIENTS)
        
        ;; Verify token balance
        (asserts! 
            (>= (unwrap! (contract-call? token-contract get-balance tx-sender) ERR-INSUFFICIENT-TOKEN-BALANCE) 
                total-payment-amount)
            ERR-INSUFFICIENT-TOKEN-BALANCE
        )
        
        ;; Distribute to active recipients
        (fold process-recipient-payment 
            (var-get recipient-list) 
            { token: token-contract, 
              amount: total-payment-amount, 
              success: true }
        )
        
        (ok true)
    )
)

(define-private (process-recipient-payment 
    (recipient principal) 
    (state { token: <fungible-token>, amount: uint, success: bool })
)
    (match (map-get? payment-recipients recipient)
        recipient-record
        (if (get is-active recipient-record)
            (let ((payment-amount (calculate-payment-share 
                    (get amount state) 
                    (get share-percentage recipient-record)
                )))
                (match (execute-token-transfer 
                        (get token state) 
                        recipient 
                        payment-amount)
                    success
                    { token: (get token state),
                      amount: (get amount state),
                      success: (and (get success state) true) }
                    error
                    { token: (get token state),
                      amount: (get amount state),
                      success: false }
                )
            )
            state
        )
        state
    )
)

;; Initialize contract
(begin
    (var-set contract-administrator tx-sender)
    (var-set cumulative-shares u0)
    (var-set recipient-list (list))
)