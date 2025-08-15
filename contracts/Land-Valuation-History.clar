(define-data-var valuation-counter uint u0)
(define-data-var registry-admin principal tx-sender)

(define-map certified-appraisers principal bool)

(define-map valuation-records
  { token-id: uint, valuation-id: uint }
  {
    appraiser: principal,
    valuation: uint,
    valuation-date: uint,
    methodology: (string-ascii 50),
    confidence-score: uint
  }
)

(define-map property-valuations
  uint
  {
    current-count: uint,
    latest-valuation: uint,
    highest-valuation: uint,
    lowest-valuation: uint,
    first-valuation-date: uint
  }
)

(define-constant ERR-NOT-APPRAISER (err u300))
(define-constant ERR-NOT-ADMIN (err u301))
(define-constant ERR-INVALID-CONFIDENCE (err u302))
(define-constant ERR-INVALID-VALUATION (err u303))
(define-constant ERR-NO-VALUATIONS (err u304))

(define-read-only (get-valuation-record (token-id uint) (valuation-id uint))
  (map-get? valuation-records { token-id: token-id, valuation-id: valuation-id })
)

(define-read-only (get-property-stats (token-id uint))
  (map-get? property-valuations token-id)
)

(define-read-only (is-certified-appraiser (appraiser principal))
  (default-to false (map-get? certified-appraisers appraiser))
)

(define-read-only (calculate-appreciation (token-id uint))
  (match (map-get? property-valuations token-id)
    stats 
    (let
      ((latest (get latest-valuation stats))
       (first-record (get-valuation-record token-id u1)))
      (match first-record
        first-val 
        (if (> (get valuation first-val) u0)
          (ok (/ (* (- latest (get valuation first-val)) u10000) (get valuation first-val)))
          (err u0))
        (err u0)))
    (err u0)
  )
)

(define-read-only (get-valuation-trend (token-id uint))
  (match (map-get? property-valuations token-id)
    stats
    (let ((count (get current-count stats)))
      (if (>= count u2)
        (let
          ((latest-opt (get-valuation-record token-id count))
           (previous-opt (get-valuation-record token-id (- count u1))))
          (if (and (is-some latest-opt) (is-some previous-opt))
            (let
              ((latest-val (unwrap-panic latest-opt))
               (previous-val (unwrap-panic previous-opt))
               (latest-amount (get valuation latest-val))
               (previous-amount (get valuation previous-val)))
              (if (>= latest-amount previous-amount)
                (ok (to-int (- latest-amount previous-amount)))
                (ok (- 0 (to-int (- previous-amount latest-amount))))))
            (ok (to-int u0))))
        (ok (to-int u0))))
    (ok (to-int u0))
  )
)

(define-public (certify-appraiser (appraiser principal))
  (begin
    (asserts! (is-eq tx-sender (var-get registry-admin)) ERR-NOT-ADMIN)
    (map-set certified-appraisers appraiser true)
    (ok true)
  )
)

(define-public (submit-valuation (token-id uint) (valuation uint) (methodology (string-ascii 50)) (confidence uint))
  (let
    ((valuation-id (+ (var-get valuation-counter) u1))
     (current-block stacks-block-height)
     (existing-stats (map-get? property-valuations token-id)))
    (asserts! (is-certified-appraiser tx-sender) ERR-NOT-APPRAISER)
    (asserts! (and (>= confidence u1) (<= confidence u100)) ERR-INVALID-CONFIDENCE)
    (asserts! (> valuation u0) ERR-INVALID-VALUATION)
    (map-set valuation-records
      { token-id: token-id, valuation-id: valuation-id }
      {
        appraiser: tx-sender,
        valuation: valuation,
        valuation-date: current-block,
        methodology: methodology,
        confidence-score: confidence
      }
    )
    (match existing-stats
      stats
      (map-set property-valuations token-id
        {
          current-count: (+ (get current-count stats) u1),
          latest-valuation: valuation,
          highest-valuation: (if (> valuation (get highest-valuation stats)) valuation (get highest-valuation stats)),
          lowest-valuation: (if (< valuation (get lowest-valuation stats)) valuation (get lowest-valuation stats)),
          first-valuation-date: (get first-valuation-date stats)
        }
      )
      (map-set property-valuations token-id
        {
          current-count: u1,
          latest-valuation: valuation,
          highest-valuation: valuation,
          lowest-valuation: valuation,
          first-valuation-date: current-block
        }
      )
    )
    (var-set valuation-counter valuation-id)
    (ok valuation-id)
  )
)