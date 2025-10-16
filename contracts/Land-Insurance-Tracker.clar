(define-data-var insurance-admin principal tx-sender)
(define-data-var policy-counter uint u0)
(define-data-var base-premium-rate uint u15)

(define-map authorized-insurers principal bool)

(define-map insurance-policies
  uint
  {
    token-id: uint,
    insurer: principal,
    policy-holder: principal,
    coverage-amount: uint,
    premium-paid: uint,
    start-date: uint,
    end-date: uint,
    status: (string-ascii 20)
  }
)

(define-map property-insurance-status
  uint
  {
    active-policy-id: (optional uint),
    total-policies: uint,
    last-premium-paid: uint,
    claims-filed: uint
  }
)

(define-constant ERR-NOT-ADMIN (err u500))
(define-constant ERR-NOT-INSURER (err u501))
(define-constant ERR-NOT-OWNER (err u502))
(define-constant ERR-POLICY-EXPIRED (err u503))
(define-constant ERR-INSUFFICIENT-COVERAGE (err u504))

(define-read-only (calculate-premium (token-id uint) (coverage-amount uint))
  (match (contract-call? .Tokenized-Land-Ownership-Registry get-land-details token-id)
    land-info
    (let
      ((land-type (get land-type land-info))
       (size (get size land-info))
       (base-rate (var-get base-premium-rate))
       (type-multiplier (if (is-eq land-type "commercial") u2 u1))
       (size-factor (/ size u100)))
      (ok (/ (* coverage-amount base-rate type-multiplier (+ u1 size-factor)) u10000)))
    (err u0)
  )
)

(define-read-only (get-policy (policy-id uint))
  (map-get? insurance-policies policy-id)
)

(define-read-only (get-property-insurance (token-id uint))
  (map-get? property-insurance-status token-id)
)

(define-read-only (is-coverage-active (token-id uint))
  (match (map-get? property-insurance-status token-id)
    status
    (match (get active-policy-id status)
      policy-id
      (match (map-get? insurance-policies policy-id)
        policy
        (and 
          (is-eq (get status policy) "active")
          (< stacks-block-height (get end-date policy)))
        false)
      false)
    false)
)

(define-public (purchase-policy (token-id uint) (coverage-amount uint) (duration uint))
  (let
    ((policy-id (+ (var-get policy-counter) u1))
     (owner (unwrap! (contract-call? .Tokenized-Land-Ownership-Registry get-owner token-id) ERR-NOT-OWNER))
     (premium (unwrap! (calculate-premium token-id coverage-amount) ERR-INSUFFICIENT-COVERAGE))
     (current-block stacks-block-height)
     (end-date (+ current-block duration)))
    (asserts! (is-some owner) ERR-NOT-OWNER)
    (try! (stx-transfer? premium tx-sender (var-get insurance-admin)))
    (map-set insurance-policies policy-id
      {
        token-id: token-id,
        insurer: (var-get insurance-admin),
        policy-holder: tx-sender,
        coverage-amount: coverage-amount,
        premium-paid: premium,
        start-date: current-block,
        end-date: end-date,
        status: "active"
      }
    )
    (map-set property-insurance-status token-id
      {
        active-policy-id: (some policy-id),
        total-policies: (+ (default-to u0 (get total-policies (map-get? property-insurance-status token-id))) u1),
        last-premium-paid: current-block,
        claims-filed: (default-to u0 (get claims-filed (map-get? property-insurance-status token-id)))
      }
    )
    (var-set policy-counter policy-id)
    (ok policy-id)
  )
)

(define-public (set-premium-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get insurance-admin)) ERR-NOT-ADMIN)
    (var-set base-premium-rate new-rate)
    (ok true)
  )
)
