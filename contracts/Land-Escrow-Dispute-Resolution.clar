(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-ESCROW (err u401))
(define-constant ERR-ESCROW-EXPIRED (err u402))
(define-constant ERR-WRONG-PARTICIPANT (err u403))
(define-constant ERR-INVALID-STATUS (err u404))
(define-constant ERR-DISPUTE-EXISTS (err u405))
(define-constant ERR-NO-MEDIATOR (err u406))

(define-data-var escrow-counter uint u0)
(define-data-var dispute-counter uint u0)
(define-data-var registry-admin principal tx-sender)

(define-map authorized-mediators principal bool)

(define-map escrow-agreements
  uint
  {
    token-id: uint,
    buyer: principal,
    seller: principal,
    escrow-amount: uint,
    service-fee: uint,
    created-at: uint,
    expires-at: uint,
    status: (string-ascii 20)
  }
)

(define-map dispute-cases
  uint
  {
    escrow-id: uint,
    initiator: principal,
    mediator: (optional principal),
    resolution: (optional (string-ascii 50)),
    created-at: uint,
    resolved-at: (optional uint)
  }
)


(define-read-only (get-escrow (escrow-id uint))
  (map-get? escrow-agreements escrow-id)
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? dispute-cases dispute-id)
)

(define-read-only (is-authorized-mediator (mediator principal))
  (default-to false (map-get? authorized-mediators mediator))
)

(define-public (create-escrow (token-id uint) (seller principal) (amount uint) (duration uint))
  (let
    ((escrow-id (+ (var-get escrow-counter) u1))
     (current-block stacks-block-height)
     (expiry (+ current-block duration))
     (service-fee (/ amount u50)))
    (try! (stx-transfer? (+ amount service-fee) tx-sender (as-contract tx-sender)))
    (map-set escrow-agreements escrow-id
      {
        token-id: token-id,
        buyer: tx-sender,
        seller: seller,
        escrow-amount: amount,
        service-fee: service-fee,
        created-at: current-block,
        expires-at: expiry,
        status: "active"
      }
    )
    (var-set escrow-counter escrow-id)
    (ok escrow-id)
  )
)

(define-public (release-escrow (escrow-id uint))
  (let
    ((escrow-data (unwrap! (map-get? escrow-agreements escrow-id) ERR-INVALID-ESCROW))
     (seller (get seller escrow-data))
     (amount (get escrow-amount escrow-data)))
    (asserts! (is-eq tx-sender (get buyer escrow-data)) ERR-WRONG-PARTICIPANT)
    (asserts! (is-eq (get status escrow-data) "active") ERR-INVALID-STATUS)
    (try! (as-contract (stx-transfer? amount tx-sender seller)))
    (map-set escrow-agreements escrow-id
      (merge escrow-data { status: "completed" })
    )
    (ok true)
  )
)

(define-public (refund-escrow (escrow-id uint))
  (let
    ((escrow-data (unwrap! (map-get? escrow-agreements escrow-id) ERR-INVALID-ESCROW))
     (buyer (get buyer escrow-data))
     (total (+ (get escrow-amount escrow-data) (get service-fee escrow-data))))
    (asserts! 
      (or 
        (is-eq tx-sender (get seller escrow-data))
        (> stacks-block-height (get expires-at escrow-data))
      ) 
      ERR-NOT-AUTHORIZED
    )
    (asserts! (is-eq (get status escrow-data) "active") ERR-INVALID-STATUS)
    (try! (as-contract (stx-transfer? total tx-sender buyer)))
    (map-set escrow-agreements escrow-id
      (merge escrow-data { status: "refunded" })
    )
    (ok true)
  )
)

(define-public (initiate-dispute (escrow-id uint))
  (let
    ((escrow-data (unwrap! (map-get? escrow-agreements escrow-id) ERR-INVALID-ESCROW))
     (dispute-id (+ (var-get dispute-counter) u1)))
    (asserts! 
      (or 
        (is-eq tx-sender (get buyer escrow-data))
        (is-eq tx-sender (get seller escrow-data))
      ) 
      ERR-WRONG-PARTICIPANT
    )
    (asserts! (is-eq (get status escrow-data) "active") ERR-INVALID-STATUS)
    (map-set dispute-cases dispute-id
      {
        escrow-id: escrow-id,
        initiator: tx-sender,
        mediator: none,
        resolution: none,
        created-at: stacks-block-height,
        resolved-at: none
      }
    )
    (map-set escrow-agreements escrow-id
      (merge escrow-data { status: "disputed" })
    )
    (var-set dispute-counter dispute-id)
    (ok dispute-id)
  )
)

(define-public (assign-mediator (dispute-id uint) (mediator principal))
  (let
    ((dispute-data (unwrap! (map-get? dispute-cases dispute-id) ERR-INVALID-ESCROW)))
    (asserts! (is-eq tx-sender (var-get registry-admin)) ERR-NOT-AUTHORIZED)
    (asserts! (is-authorized-mediator mediator) ERR-NOT-AUTHORIZED)
    (map-set dispute-cases dispute-id
      (merge dispute-data { mediator: (some mediator) })
    )
    (ok true)
  )
)

(define-public (resolve-dispute (dispute-id uint) (resolution (string-ascii 50)) (award-to-buyer bool))
  (let
    ((dispute-data (unwrap! (map-get? dispute-cases dispute-id) ERR-INVALID-ESCROW))
     (escrow-data (unwrap! (map-get? escrow-agreements (get escrow-id dispute-data)) ERR-INVALID-ESCROW))
     (amount (get escrow-amount escrow-data)))
    (asserts! 
      (is-eq tx-sender (unwrap! (get mediator dispute-data) ERR-NO-MEDIATOR)) 
      ERR-NOT-AUTHORIZED
    )
    (if award-to-buyer
      (try! (as-contract (stx-transfer? amount tx-sender (get buyer escrow-data))))
      (try! (as-contract (stx-transfer? amount tx-sender (get seller escrow-data))))
    )
    (map-set dispute-cases dispute-id
      (merge dispute-data { 
        resolution: (some resolution),
        resolved-at: (some stacks-block-height)
      })
    )
    (map-set escrow-agreements (get escrow-id dispute-data)
      (merge escrow-data { status: "resolved" })
    )
    (ok true)
  )
)

(define-public (authorize-mediator (mediator principal))
  (begin
    (asserts! (is-eq tx-sender (var-get registry-admin)) ERR-NOT-AUTHORIZED)
    (map-set authorized-mediators mediator true)
    (ok true)
  )
)
