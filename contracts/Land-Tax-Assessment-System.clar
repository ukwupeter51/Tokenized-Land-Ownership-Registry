(define-data-var tax-rate uint u25)
(define-data-var collection-period uint u5040)
(define-data-var tax-collector principal tx-sender)
(define-data-var penalty-rate uint u10)

(define-map tax-assessments
  uint
  {
    assessed-value: uint,
    tax-due: uint,
    due-date: uint,
    last-payment: uint,
    payment-count: uint,
    penalty-amount: uint
  }
)

(define-map tax-payments
  { token-id: uint, payment-id: uint }
  {
    amount: uint,
    payment-date: uint,
    payer: principal,
    penalty-paid: uint
  }
)

(define-data-var payment-counter uint u0)

(define-constant ERR-NOT-COLLECTOR (err u200))
(define-constant ERR-INVALID-AMOUNT (err u201))
(define-constant ERR-NO-ASSESSMENT (err u202))
(define-constant ERR-ALREADY-PAID (err u203))

(define-read-only (get-tax-assessment (token-id uint))
  (map-get? tax-assessments token-id)
)

(define-read-only (calculate-tax (market-value uint))
  (/ (* market-value (var-get tax-rate)) u1000)
)

(define-read-only (calculate-penalty (base-amount uint) (blocks-overdue uint))
  (if (> blocks-overdue u0)
    (/ (* base-amount (var-get penalty-rate) blocks-overdue) u10000)
    u0
  )
)

(define-read-only (get-payment-history (token-id uint) (payment-id uint))
  (map-get? tax-payments { token-id: token-id, payment-id: payment-id })
)

(define-read-only (is-tax-current (token-id uint))
  (match (map-get? tax-assessments token-id)
    assessment (>= (get last-payment assessment) (get due-date assessment))
    true
  )
)

(define-public (assess-land-tax (token-id uint))
  (let
    (
      (land-info (unwrap! (contract-call? .Tokenized-Land-Ownership-Registry get-land-details token-id) ERR-NO-ASSESSMENT))
      (land-value (get market-value land-info))
      (tax-amount (calculate-tax land-value))
      (current-block stacks-block-height)
      (due-date (+ current-block (var-get collection-period)))
    )
    (asserts! (is-eq tx-sender (var-get tax-collector)) ERR-NOT-COLLECTOR)
    (map-set tax-assessments token-id
      {
        assessed-value: land-value,
        tax-due: tax-amount,
        due-date: due-date,
        last-payment: u0,
        payment-count: u0,
        penalty-amount: u0
      }
    )
    (ok tax-amount)
  )
)

(define-public (pay-tax (token-id uint))
  (let
    (
      (assessment (unwrap! (map-get? tax-assessments token-id) ERR-NO-ASSESSMENT))
      (current-block stacks-block-height)
      (blocks-overdue (if (> current-block (get due-date assessment)) 
        (- current-block (get due-date assessment)) 
        u0))
      (penalty (calculate-penalty (get tax-due assessment) blocks-overdue))
      (total-due (+ (get tax-due assessment) penalty))
      (payment-id (+ (var-get payment-counter) u1))
    )
    (try! (stx-transfer? total-due tx-sender (var-get tax-collector)))
    (map-set tax-payments 
      { token-id: token-id, payment-id: payment-id }
      {
        amount: (get tax-due assessment),
        payment-date: current-block,
        payer: tx-sender,
        penalty-paid: penalty
      }
    )
    (map-set tax-assessments token-id
      (merge assessment {
        last-payment: current-block,
        payment-count: (+ (get payment-count assessment) u1),
        penalty-amount: penalty
      })
    )
    (var-set payment-counter payment-id)
    (ok total-due)
  )
)

(define-public (set-tax-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get tax-collector)) ERR-NOT-COLLECTOR)
    (var-set tax-rate new-rate)
    (ok true)
  )
)

(define-public (set-collection-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender (var-get tax-collector)) ERR-NOT-COLLECTOR)
    (var-set collection-period new-period)
    (ok true)
  )
)

(define-public (transfer-collector-role (new-collector principal))
  (begin
    (asserts! (is-eq tx-sender (var-get tax-collector)) ERR-NOT-COLLECTOR)
    (var-set tax-collector new-collector)
    (ok true)
  )
)