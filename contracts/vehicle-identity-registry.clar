;; Vehicle Identity Registry Contract
;; Register vehicle VIN numbers with manufacturing details and ownership transfer history

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-VIN (err u103))
(define-constant ERR-UNAUTHORIZED (err u104))
(define-constant ERR-INVALID-TRANSFER (err u105))

;; Data structures
(define-map vehicles 
  { vin: (string-ascii 17) }
  { 
    make: (string-ascii 50),
    model: (string-ascii 50),
    year: uint,
    color: (string-ascii 30),
    owner: principal,
    registration-date: uint,
    status: (string-ascii 20),
    mileage: uint,
    is-active: bool
  }
)

(define-map ownership-history
  { vin: (string-ascii 17), transfer-id: uint }
  {
    previous-owner: principal,
    new-owner: principal,
    transfer-date: uint,
    transfer-price: (optional uint),
    verified: bool
  }
)

(define-map vehicle-transfer-count
  { vin: (string-ascii 17) }
  { count: uint }
)

(define-map authorized-dealers
  { dealer: principal }
  { 
    name: (string-ascii 100),
    license-number: (string-ascii 50),
    authorized-date: uint,
    is-active: bool
  }
)

(define-data-var next-transfer-id uint u1)

;; Private functions
(define-private (is-valid-vin (vin (string-ascii 17)))
  (is-eq (len vin) u17)
)

(define-private (is-authorized-dealer (dealer principal))
  (match (map-get? authorized-dealers { dealer: dealer })
    dealer-info (get is-active dealer-info)
    false
  )
)

(define-private (increment-transfer-id)
  (let ((current-id (var-get next-transfer-id)))
    (var-set next-transfer-id (+ current-id u1))
    current-id
  )
)

;; Public functions
(define-public (register-vehicle 
  (vin (string-ascii 17))
  (make (string-ascii 50))
  (model (string-ascii 50))
  (year uint)
  (color (string-ascii 30))
  (initial-mileage uint)
)
  (begin
    (asserts! (is-valid-vin vin) ERR-INVALID-VIN)
    (asserts! (is-none (map-get? vehicles { vin: vin })) ERR-ALREADY-EXISTS)
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-authorized-dealer tx-sender)) ERR-UNAUTHORIZED)
    
    (map-set vehicles
      { vin: vin }
      {
        make: make,
        model: model,
        year: year,
        color: color,
        owner: tx-sender,
        registration-date: stacks-block-height,
        status: "registered",
        mileage: initial-mileage,
        is-active: true
      }
    )
    
    (map-set vehicle-transfer-count
      { vin: vin }
      { count: u0 }
    )
    
    (ok vin)
  )
)

(define-public (transfer-ownership
  (vin (string-ascii 17))
  (new-owner principal)
  (transfer-price (optional uint))
)
  (let 
    (
      (vehicle-data (unwrap! (map-get? vehicles { vin: vin }) ERR-NOT-FOUND))
      (current-owner (get owner vehicle-data))
      (transfer-id (increment-transfer-id))
      (transfer-count-data (unwrap! (map-get? vehicle-transfer-count { vin: vin }) ERR-NOT-FOUND))
      (current-count (get count transfer-count-data))
    )
    
    (asserts! (is-eq tx-sender current-owner) ERR-UNAUTHORIZED)
    (asserts! (not (is-eq current-owner new-owner)) ERR-INVALID-TRANSFER)
    (asserts! (get is-active vehicle-data) ERR-NOT-FOUND)
    
    ;; Update vehicle ownership
    (map-set vehicles
      { vin: vin }
      (merge vehicle-data { owner: new-owner })
    )
    
    ;; Record ownership transfer
    (map-set ownership-history
      { vin: vin, transfer-id: transfer-id }
      {
        previous-owner: current-owner,
        new-owner: new-owner,
        transfer-date: stacks-block-height,
        transfer-price: transfer-price,
        verified: false
      }
    )
    
    ;; Update transfer count
    (map-set vehicle-transfer-count
      { vin: vin }
      { count: (+ current-count u1) }
    )
    
    (ok transfer-id)
  )
)

(define-public (verify-transfer
  (vin (string-ascii 17))
  (transfer-id uint)
)
  (let 
    (
      (transfer-data (unwrap! (map-get? ownership-history { vin: vin, transfer-id: transfer-id }) ERR-NOT-FOUND))
    )
    
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-authorized-dealer tx-sender)) ERR-UNAUTHORIZED)
    
    (map-set ownership-history
      { vin: vin, transfer-id: transfer-id }
      (merge transfer-data { verified: true })
    )
    
    (ok true)
  )
)

(define-public (update-vehicle-status
  (vin (string-ascii 17))
  (new-status (string-ascii 20))
)
  (let 
    (
      (vehicle-data (unwrap! (map-get? vehicles { vin: vin }) ERR-NOT-FOUND))
    )
    
    (asserts! (is-eq tx-sender (get owner vehicle-data)) ERR-UNAUTHORIZED)
    (asserts! (get is-active vehicle-data) ERR-NOT-FOUND)
    
    (map-set vehicles
      { vin: vin }
      (merge vehicle-data { status: new-status })
    )
    
    (ok true)
  )
)

(define-public (update-mileage
  (vin (string-ascii 17))
  (new-mileage uint)
)
  (let 
    (
      (vehicle-data (unwrap! (map-get? vehicles { vin: vin }) ERR-NOT-FOUND))
      (current-mileage (get mileage vehicle-data))
    )
    
    (asserts! (is-eq tx-sender (get owner vehicle-data)) ERR-UNAUTHORIZED)
    (asserts! (get is-active vehicle-data) ERR-NOT-FOUND)
    (asserts! (>= new-mileage current-mileage) ERR-INVALID-VIN)
    
    (map-set vehicles
      { vin: vin }
      (merge vehicle-data { mileage: new-mileage })
    )
    
    (ok new-mileage)
  )
)

(define-public (authorize-dealer
  (dealer principal)
  (name (string-ascii 100))
  (license-number (string-ascii 50))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set authorized-dealers
      { dealer: dealer }
      {
        name: name,
        license-number: license-number,
        authorized-date: stacks-block-height,
        is-active: true
      }
    )
    
    (ok true)
  )
)

(define-public (deactivate-vehicle
  (vin (string-ascii 17))
)
  (let 
    (
      (vehicle-data (unwrap! (map-get? vehicles { vin: vin }) ERR-NOT-FOUND))
    )
    
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get owner vehicle-data))) ERR-UNAUTHORIZED)
    
    (map-set vehicles
      { vin: vin }
      (merge vehicle-data { is-active: false, status: "deactivated" })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-vehicle-info (vin (string-ascii 17)))
  (map-get? vehicles { vin: vin })
)

(define-read-only (get-vehicle-owner (vin (string-ascii 17)))
  (match (map-get? vehicles { vin: vin })
    vehicle-data (some (get owner vehicle-data))
    none
  )
)

(define-read-only (get-ownership-history (vin (string-ascii 17)) (transfer-id uint))
  (map-get? ownership-history { vin: vin, transfer-id: transfer-id })
)

(define-read-only (get-transfer-count (vin (string-ascii 17)))
  (match (map-get? vehicle-transfer-count { vin: vin })
    count-data (some (get count count-data))
    none
  )
)

(define-read-only (is-vehicle-active (vin (string-ascii 17)))
  (match (map-get? vehicles { vin: vin })
    vehicle-data (get is-active vehicle-data)
    false
  )
)

(define-read-only (get-dealer-info (dealer principal))
  (map-get? authorized-dealers { dealer: dealer })
)
