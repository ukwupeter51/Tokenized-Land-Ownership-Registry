(define-data-var rental-counter uint u0)
(define-data-var platform-fee-rate uint u5)
(define-data-var platform-admin principal tx-sender)

(define-map active-rentals
  uint
  {
    token-id: uint,
    landlord: principal,
    tenant: principal,
    monthly-rent: uint,
    deposit-amount: uint,
    lease-start: uint,
    lease-end: uint,
    last-rent-paid: uint,
    grace-period: uint,
    status: (string-ascii 20)
  }
)

(define-map property-rental-status
  uint
  {
    is-rented: bool,
    current-rental-id: (optional uint),
    total-rent-collected: uint,
    rental-count: uint
  }
)

(define-constant ERR-NOT-OWNER (err u600))
(define-constant ERR-ALREADY-RENTED (err u601))
(define-constant ERR-INVALID-RENTAL (err u602))
(define-constant ERR-PAYMENT-OVERDUE (err u603))
(define-constant ERR-NOT-TENANT (err u604))
(define-constant ERR-LEASE-EXPIRED (err u605))
(define-constant ERR-NOT-ADMIN (err u606))

(define-read-only (get-rental (rental-id uint))
  (map-get? active-rentals rental-id)
)

(define-read-only (get-property-rental (token-id uint))
  (map-get? property-rental-status token-id)
)

(define-read-only (calculate-rent-due (rental-id uint))
  (match (map-get? active-rentals rental-id)
    rental
    (let
      ((last-paid (get last-rent-paid rental))
       (current-block stacks-block-height)
       (monthly-rent (get monthly-rent rental))
       (blocks-passed (- current-block last-paid))
       (months-due (/ blocks-passed u4320)))
      (ok (* monthly-rent months-due)))
    (err u0)
  )
)

(define-public (create-rental (token-id uint) (tenant principal) (monthly-rent uint) (deposit uint) (duration uint) (grace uint))
  (let
    ((rental-id (+ (var-get rental-counter) u1))
     (owner-opt (unwrap! (contract-call? .Tokenized-Land-Ownership-Registry get-owner token-id) ERR-NOT-OWNER))
     (current-block stacks-block-height)
     (lease-end (+ current-block duration)))
    (asserts! (is-eq (some tx-sender) owner-opt) ERR-NOT-OWNER)
    (asserts! (is-none (get current-rental-id (default-to { is-rented: false, current-rental-id: none, total-rent-collected: u0, rental-count: u0 } (map-get? property-rental-status token-id)))) ERR-ALREADY-RENTED)
    (map-set active-rentals rental-id
      {
        token-id: token-id,
        landlord: tx-sender,
        tenant: tenant,
        monthly-rent: monthly-rent,
        deposit-amount: deposit,
        lease-start: current-block,
        lease-end: lease-end,
        last-rent-paid: current-block,
        grace-period: grace,
        status: "pending"
      }
    )
    (map-set property-rental-status token-id
      {
        is-rented: false,
        current-rental-id: (some rental-id),
        total-rent-collected: u0,
        rental-count: (+ (default-to u0 (get rental-count (map-get? property-rental-status token-id))) u1)
      }
    )
    (var-set rental-counter rental-id)
    (ok rental-id)
  )
)

(define-public (activate-rental (rental-id uint))
  (let
    ((rental (unwrap! (map-get? active-rentals rental-id) ERR-INVALID-RENTAL))
     (total-due (+ (get monthly-rent rental) (get deposit-amount rental)))
     (platform-fee (/ (* total-due (var-get platform-fee-rate)) u100)))
    (asserts! (is-eq tx-sender (get tenant rental)) ERR-NOT-TENANT)
    (asserts! (is-eq (get status rental) "pending") ERR-INVALID-RENTAL)
    (try! (stx-transfer? (- total-due platform-fee) tx-sender (get landlord rental)))
    (try! (stx-transfer? platform-fee tx-sender (var-get platform-admin)))
    (map-set active-rentals rental-id (merge rental { status: "active" }))
    (map-set property-rental-status (get token-id rental) 
      (merge (unwrap-panic (map-get? property-rental-status (get token-id rental))) { is-rented: true })
    )
    (ok true)
  )
)

(define-public (pay-rent (rental-id uint))
  (let
    ((rental (unwrap! (map-get? active-rentals rental-id) ERR-INVALID-RENTAL))
     (rent-due (unwrap! (calculate-rent-due rental-id) ERR-INVALID-RENTAL))
     (platform-fee (/ (* rent-due (var-get platform-fee-rate)) u100)))
    (asserts! (is-eq tx-sender (get tenant rental)) ERR-NOT-TENANT)
    (asserts! (is-eq (get status rental) "active") ERR-INVALID-RENTAL)
    (try! (stx-transfer? (- rent-due platform-fee) tx-sender (get landlord rental)))
    (try! (stx-transfer? platform-fee tx-sender (var-get platform-admin)))
    (map-set active-rentals rental-id 
      (merge rental { last-rent-paid: stacks-block-height })
    )
    (map-set property-rental-status (get token-id rental)
      (merge (unwrap-panic (map-get? property-rental-status (get token-id rental))) 
        { total-rent-collected: (+ (get total-rent-collected (unwrap-panic (map-get? property-rental-status (get token-id rental)))) rent-due) }
      )
    )
    (ok rent-due)
  )
)

(define-public (terminate-rental (rental-id uint))
  (let
    ((rental (unwrap! (map-get? active-rentals rental-id) ERR-INVALID-RENTAL)))
    (asserts! 
      (or 
        (is-eq tx-sender (get landlord rental))
        (is-eq tx-sender (get tenant rental))
      ) 
      ERR-NOT-OWNER
    )
    (map-set active-rentals rental-id (merge rental { status: "terminated" }))
    (map-set property-rental-status (get token-id rental)
      (merge (unwrap-panic (map-get? property-rental-status (get token-id rental))) 
        { is-rented: false, current-rental-id: none }
      )
    )
    (ok true)
  )
)
