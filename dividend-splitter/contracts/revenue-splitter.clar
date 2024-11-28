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

;; Read-only functions
(define-read-only (get-recipient-details (recipient-address principal))
    (default-to 
        { share-percentage: u0, is-active: false }
        (map-get? payment-recipients recipient-address))
)

(define-read-only (get-cumulative-shares)
    (var-get cumulative-shares)
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
            (ok true)
        )
    )
)

(define-public (unregister-recipient (recipient-address principal))
    (begin
        (asserts! (is-contract-admin tx-sender) ERR-UNAUTHORIZED-ACCESS)
        (match (map-get? payment-recipients recipient-address)
            recipient-record
            (begin
                (var-set cumulative-shares (- (var-get cumulative-shares) (get share-percentage recipient-record)))
                (map-delete payment-recipients recipient-address)
                (ok true)
            )
            (err ERR-RECIPIENT-NOT-FOUND)
        )
    )
)

(define-public (modify-recipient-share (recipient-address principal) (updated-share-percentage uint))
    (begin
        (asserts! (is-contract-admin tx-sender) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> updated-share-percentage u0) ERR-INVALID-SHARE-AMOUNT)
        
        (match (map-get? payment-recipients recipient-address)
            recipient-record
            (let (
                (current-share (get share-percentage recipient-record))
                (new-total-shares (+ (- (var-get cumulative-shares) current-share) updated-share-percentage))
            )
                (asserts! (<= new-total-shares u10000) ERR-TOTAL-SHARES-EXCEEDED)
                (map-set payment-recipients 
                    recipient-address 
                    { share-percentage: updated-share-percentage, is-active: (get is-active recipient-record) }
                )
                (var-set cumulative-shares new-total-shares)
                (ok true)
            )
            (err ERR-RECIPIENT-NOT-FOUND)
        )
    )
)

(define-public (toggle-recipient-status (recipient-address principal))
    (begin
        (asserts! (is-contract-admin tx-sender) ERR-UNAUTHORIZED-ACCESS)
        (match (map-get? payment-recipients recipient-address)
            recipient-record
            (begin
                (map-set payment-recipients 
                    recipient-address 
                    { share-percentage: (get share-percentage recipient-record), 
                      is-active: (not (get is-active recipient-record)) }
                )
                (ok true)
            )
            (err ERR-RECIPIENT-NOT-FOUND)
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
        (map-get payment-recipients
            (lambda (recipient-principal recipient-record)
                (if (get is-active recipient-record)
                    (let ((recipient-payment-amount (calculate-payment-share total-payment-amount (get share-percentage recipient-record))))
                        (unwrap! 
                            (execute-token-transfer token-contract recipient-principal recipient-payment-amount)
                            ERR-INSUFFICIENT-TOKEN-BALANCE
                        )
                    )
                    true
                )
            )
        )
        (ok true)
    )
)

;; Initialize contract
(begin
    (var-set contract-administrator tx-sender)
    (var-set cumulative-shares u0)
)