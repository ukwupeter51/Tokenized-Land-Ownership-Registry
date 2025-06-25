(define-non-fungible-token land-deed uint)

(define-data-var last-token-id uint u0)
(define-data-var contract-owner principal tx-sender)

(define-map land-registry
  uint
  {
    coordinates: (string-ascii 100),
    size: uint,
    land-type: (string-ascii 50),
    registered-at: uint,
    verified: bool,
    market-value: uint
  }
)

(define-map land-transfers
  uint
  {
    from: principal,
    to: principal,
    transfer-date: uint,
    transfer-price: uint
  }
)

(define-map pending-transfers
  uint
  {
    buyer: principal,
    seller: principal,
    agreed-price: uint,
    expires-at: uint
  }
)

(define-map authorized-surveyors principal bool)

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-NOT-OWNER (err u102))
(define-constant ERR-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-TRANSFER (err u104))
(define-constant ERR-TRANSFER-EXPIRED (err u105))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u106))
(define-constant ERR-LAND-NOT-VERIFIED (err u107))

(define-read-only (get-last-token-id)
  (var-get last-token-id)
)

(define-read-only (get-token-uri (token-id uint))
  (ok none)
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? land-deed token-id))
)

(define-read-only (get-land-details (token-id uint))
  (map-get? land-registry token-id)
)

(define-read-only (get-transfer-history (token-id uint))
  (map-get? land-transfers token-id)
)

(define-read-only (get-pending-transfer (token-id uint))
  (map-get? pending-transfers token-id)
)

(define-read-only (is-authorized-surveyor (surveyor principal))
  (default-to false (map-get? authorized-surveyors surveyor))
)

(define-public (register-land (coordinates (string-ascii 100)) (size uint) (land-type (string-ascii 50)) (market-value uint))
  (let
    (
      (token-id (+ (var-get last-token-id) u1))
      (current-block stacks-block-height)
    )
    (asserts! (is-authorized-surveyor tx-sender) ERR-NOT-AUTHORIZED)
    (try! (nft-mint? land-deed token-id tx-sender))
    (map-set land-registry token-id
      {
        coordinates: coordinates,
        size: size,
        land-type: land-type,
        registered-at: current-block,
        verified: false,
        market-value: market-value
      }
    )
    (var-set last-token-id token-id)
    (ok token-id)
  )
)

(define-public (verify-land (token-id uint))
  (let
    (
      (land-data (unwrap! (map-get? land-registry token-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set land-registry token-id
      (merge land-data { verified: true })
    )
    (ok true)
  )
)

(define-public (initiate-transfer (token-id uint) (buyer principal) (agreed-price uint))
  (let
    (
      (current-owner (unwrap! (nft-get-owner? land-deed token-id) ERR-NOT-FOUND))
      (land-data (unwrap! (map-get? land-registry token-id) ERR-NOT-FOUND))
      (expires-at (+ stacks-block-height u144))
    )
    (asserts! (is-eq tx-sender current-owner) ERR-NOT-OWNER)
    (asserts! (get verified land-data) ERR-LAND-NOT-VERIFIED)
    (map-set pending-transfers token-id
      {
        buyer: buyer,
        seller: tx-sender,
        agreed-price: agreed-price,
        expires-at: expires-at
      }
    )
    (ok true)
  )
)

(define-public (complete-transfer (token-id uint))
  (let
    (
      (transfer-data (unwrap! (map-get? pending-transfers token-id) ERR-NOT-FOUND))
      (current-block stacks-block-height)
      (buyer (get buyer transfer-data))
      (seller (get seller transfer-data))
      (agreed-price (get agreed-price transfer-data))
    )
    (asserts! (is-eq tx-sender buyer) ERR-NOT-AUTHORIZED)
    (asserts! (< current-block (get expires-at transfer-data)) ERR-TRANSFER-EXPIRED)
    (try! (stx-transfer? agreed-price tx-sender seller))
    (try! (nft-transfer? land-deed token-id seller buyer))
    (map-set land-transfers token-id
      {
        from: seller,
        to: buyer,
        transfer-date: current-block,
        transfer-price: agreed-price
      }
    )
    (map-delete pending-transfers token-id)
    (ok true)
  )
)

(define-public (cancel-transfer (token-id uint))
  (let
    (
      (transfer-data (unwrap! (map-get? pending-transfers token-id) ERR-NOT-FOUND))
    )
    (asserts! (or 
      (is-eq tx-sender (get seller transfer-data))
      (is-eq tx-sender (get buyer transfer-data))
      (> stacks-block-height (get expires-at transfer-data))
    ) ERR-NOT-AUTHORIZED)
    (map-delete pending-transfers token-id)
    (ok true)
  )
)

(define-public (update-market-value (token-id uint) (new-value uint))
  (let
    (
      (current-owner (unwrap! (nft-get-owner? land-deed token-id) ERR-NOT-FOUND))
      (land-data (unwrap! (map-get? land-registry token-id) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender current-owner) ERR-NOT-OWNER)
    (map-set land-registry token-id
      (merge land-data { market-value: new-value })
    )
    (ok true)
  )
)

(define-public (authorize-surveyor (surveyor principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-set authorized-surveyors surveyor true)
    (ok true)
  )
)

(define-public (revoke-surveyor (surveyor principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (map-delete authorized-surveyors surveyor)
    (ok true)
  )
)

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) ERR-NOT-AUTHORIZED)
    (nft-transfer? land-deed token-id sender recipient)
  )
)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

(define-read-only (is-land-owned-by (token-id uint) (owner principal))
  (is-eq (some owner) (nft-get-owner? land-deed token-id))
)

(define-read-only (is-land-verified (token-id uint))
  (match (map-get? land-registry token-id)
    land-data (get verified land-data)
    false
  )
)

(define-read-only (get-land-count)
  (var-get last-token-id)
)

(define-read-only (get-land-coordinates (token-id uint))
  (match (map-get? land-registry token-id)
    land-data (some (get coordinates land-data))
    none
  )
)

(define-read-only (get-land-size (token-id uint))
  (match (map-get? land-registry token-id)
    land-data (some (get size land-data))
    none
  )
)

(define-read-only (get-land-type (token-id uint))
  (match (map-get? land-registry token-id)
    land-data (some (get land-type land-data))
    none
  )
)

(define-read-only (get-land-market-value (token-id uint))
  (match (map-get? land-registry token-id)
    land-data (some (get market-value land-data))
    none
  )
)

(define-read-only (get-land-registration-block (token-id uint))
  (match (map-get? land-registry token-id)
    land-data (some (get registered-at land-data))
    none
  )
)

(define-read-only (has-pending-transfer (token-id uint))
  (is-some (map-get? pending-transfers token-id))
)

(define-read-only (get-transfer-buyer (token-id uint))
  (match (map-get? pending-transfers token-id)
    transfer-data (some (get buyer transfer-data))
    none
  )
)

(define-read-only (get-transfer-seller (token-id uint))
  (match (map-get? pending-transfers token-id)
    transfer-data (some (get seller transfer-data))
    none
  )
)

(define-read-only (get-transfer-price (token-id uint))
  (match (map-get? pending-transfers token-id)
    transfer-data (some (get agreed-price transfer-data))
    none
  )
)

(define-read-only (get-transfer-expiry (token-id uint))
  (match (map-get? pending-transfers token-id)
    transfer-data (some (get expires-at transfer-data))
    none
  )
)

(define-read-only (is-transfer-expired (token-id uint))
  (match (map-get? pending-transfers token-id)
    transfer-data (> stacks-block-height (get expires-at transfer-data))
    false
  )
)

(define-read-only (get-last-transfer-from (token-id uint))
  (match (map-get? land-transfers token-id)
    transfer-data (some (get from transfer-data))
    none
  )
)

(define-read-only (get-last-transfer-to (token-id uint))
  (match (map-get? land-transfers token-id)
    transfer-data (some (get to transfer-data))
    none
  )
)

(define-read-only (get-last-transfer-date (token-id uint))
  (match (map-get? land-transfers token-id)
    transfer-data (some (get transfer-date transfer-data))
    none
  )
)

(define-read-only (get-last-transfer-price (token-id uint))
  (match (map-get? land-transfers token-id)
    transfer-data (some (get transfer-price transfer-data))
    none
  )
)
