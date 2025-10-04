;; Maintenance Record System Contract
;; Track all vehicle maintenance, repairs, and inspections with certified mechanic verification

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-FOUND (err u201))
(define-constant ERR-UNAUTHORIZED (err u202))
(define-constant ERR-INVALID-DATA (err u203))
(define-constant ERR-ALREADY-VERIFIED (err u204))
(define-constant ERR-INVALID-MILEAGE (err u205))
(define-constant ERR-INVALID-SERVICE (err u206))

;; Data structures
(define-map maintenance-records
  { vin: (string-ascii 17), record-id: uint }
  {
    service-type: (string-ascii 100),
    description: (string-ascii 500),
    service-date: uint,
    mileage: uint,
    cost: uint,
    mechanic: principal,
    shop-name: (string-ascii 200),
    parts-used: (string-ascii 300),
    verified: bool,
    verification-date: (optional uint),
    next-service-due: (optional uint),
    warranty-period: (optional uint)
  }
)

(define-map vehicle-maintenance-count
  { vin: (string-ascii 17) }
  { count: uint }
)

(define-map certified-mechanics
  { mechanic: principal }
  {
    name: (string-ascii 100),
    certification-number: (string-ascii 50),
    specializations: (string-ascii 200),
    shop-affiliation: (string-ascii 200),
    certification-date: uint,
    is-active: bool
  }
)

(define-map service-categories
  { category: (string-ascii 50) }
  {
    description: (string-ascii 200),
    typical-interval: uint,
    is-critical: bool
  }
)

(define-map mechanic-reputation
  { mechanic: principal }
  {
    total-services: uint,
    verified-services: uint,
    rating-sum: uint,
    rating-count: uint
  }
)

(define-data-var next-record-id uint u1)

;; Private functions
(define-private (is-certified-mechanic (mechanic principal))
  (match (map-get? certified-mechanics { mechanic: mechanic })
    mechanic-info (get is-active mechanic-info)
    false
  )
)

(define-private (increment-record-id)
  (let ((current-id (var-get next-record-id)))
    (var-set next-record-id (+ current-id u1))
    current-id
  )
)

(define-private (update-mechanic-stats (mechanic principal) (verified bool))
  (let (
    (current-rep (default-to 
      { total-services: u0, verified-services: u0, rating-sum: u0, rating-count: u0 }
      (map-get? mechanic-reputation { mechanic: mechanic })
    ))
    (new-total (+ (get total-services current-rep) u1))
    (new-verified (if verified (+ (get verified-services current-rep) u1) (get verified-services current-rep)))
  )
    (map-set mechanic-reputation
      { mechanic: mechanic }
      (merge current-rep {
        total-services: new-total,
        verified-services: new-verified
      })
    )
  )
)

(define-private (calculate-next-service-due (service-type (string-ascii 100)) (current-mileage uint))
  ;; For now, return a default service interval since service-type is 100 chars but category key is 50
  ;; In a real implementation, you'd truncate or use a mapping table
  (some (+ current-mileage u5000)) ;; Default 5000 mile interval
)

;; Public functions
(define-public (add-maintenance-record
  (vin (string-ascii 17))
  (service-type (string-ascii 100))
  (description (string-ascii 500))
  (mileage uint)
  (cost uint)
  (shop-name (string-ascii 200))
  (parts-used (string-ascii 300))
  (warranty-period (optional uint))
)
  (let (
    (record-id (increment-record-id))
    (maintenance-count-data (default-to { count: u0 } (map-get? vehicle-maintenance-count { vin: vin })))
    (current-count (get count maintenance-count-data))
    (next-service (calculate-next-service-due service-type mileage))
  )
    
    (asserts! (> (len vin) u0) ERR-INVALID-DATA)
    (asserts! (> (len service-type) u0) ERR-INVALID-DATA)
    (asserts! (> mileage u0) ERR-INVALID-MILEAGE)
    
    ;; Add maintenance record
    (map-set maintenance-records
      { vin: vin, record-id: record-id }
      {
        service-type: service-type,
        description: description,
        service-date: stacks-block-height,
        mileage: mileage,
        cost: cost,
        mechanic: tx-sender,
        shop-name: shop-name,
        parts-used: parts-used,
        verified: (is-certified-mechanic tx-sender),
        verification-date: (if (is-certified-mechanic tx-sender) (some stacks-block-height) none),
        next-service-due: next-service,
        warranty-period: warranty-period
      }
    )
    
    ;; Update maintenance count
    (map-set vehicle-maintenance-count
      { vin: vin }
      { count: (+ current-count u1) }
    )
    
    ;; Update mechanic stats
    (update-mechanic-stats tx-sender (is-certified-mechanic tx-sender))
    
    (ok record-id)
  )
)

(define-public (verify-maintenance-record
  (vin (string-ascii 17))
  (record-id uint)
)
  (let (
    (record-data (unwrap! (map-get? maintenance-records { vin: vin, record-id: record-id }) ERR-NOT-FOUND))
  )
    
    (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-certified-mechanic tx-sender)) ERR-UNAUTHORIZED)
    (asserts! (not (get verified record-data)) ERR-ALREADY-VERIFIED)
    
    (map-set maintenance-records
      { vin: vin, record-id: record-id }
      (merge record-data {
        verified: true,
        verification-date: (some stacks-block-height)
      })
    )
    
    ;; Update mechanic reputation
    (update-mechanic-stats (get mechanic record-data) true)
    
    (ok true)
  )
)

(define-public (certify-mechanic
  (mechanic principal)
  (name (string-ascii 100))
  (certification-number (string-ascii 50))
  (specializations (string-ascii 200))
  (shop-affiliation (string-ascii 200))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set certified-mechanics
      { mechanic: mechanic }
      {
        name: name,
        certification-number: certification-number,
        specializations: specializations,
        shop-affiliation: shop-affiliation,
        certification-date: stacks-block-height,
        is-active: true
      }
    )
    
    ;; Initialize reputation
    (map-set mechanic-reputation
      { mechanic: mechanic }
      {
        total-services: u0,
        verified-services: u0,
        rating-sum: u0,
        rating-count: u0
      }
    )
    
    (ok true)
  )
)

(define-public (add-service-category
  (category (string-ascii 50))
  (description (string-ascii 200))
  (typical-interval uint)
  (is-critical bool)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set service-categories
      { category: category }
      {
        description: description,
        typical-interval: typical-interval,
        is-critical: is-critical
      }
    )
    
    (ok true)
  )
)

(define-public (rate-mechanic
  (mechanic principal)
  (rating uint)
)
  (let (
    (current-rep (unwrap! (map-get? mechanic-reputation { mechanic: mechanic }) ERR-NOT-FOUND))
    (new-rating-sum (+ (get rating-sum current-rep) rating))
    (new-rating-count (+ (get rating-count current-rep) u1))
  )
    
    (asserts! (and (>= rating u1) (<= rating u5)) ERR-INVALID-DATA)
    
    (map-set mechanic-reputation
      { mechanic: mechanic }
      (merge current-rep {
        rating-sum: new-rating-sum,
        rating-count: new-rating-count
      })
    )
    
    (ok true)
  )
)

(define-public (update-maintenance-record
  (vin (string-ascii 17))
  (record-id uint)
  (new-description (string-ascii 500))
  (additional-parts (string-ascii 300))
)
  (let (
    (record-data (unwrap! (map-get? maintenance-records { vin: vin, record-id: record-id }) ERR-NOT-FOUND))
  )
    
    (asserts! (is-eq tx-sender (get mechanic record-data)) ERR-UNAUTHORIZED)
    (asserts! (not (get verified record-data)) ERR-ALREADY-VERIFIED)
    
    (map-set maintenance-records
      { vin: vin, record-id: record-id }
      (merge record-data {
        description: new-description,
        parts-used: additional-parts
      })
    )
    
    (ok true)
  )
)

(define-public (deactivate-mechanic
  (mechanic principal)
)
  (let (
    (mechanic-data (unwrap! (map-get? certified-mechanics { mechanic: mechanic }) ERR-NOT-FOUND))
  )
    
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    
    (map-set certified-mechanics
      { mechanic: mechanic }
      (merge mechanic-data { is-active: false })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-maintenance-record (vin (string-ascii 17)) (record-id uint))
  (map-get? maintenance-records { vin: vin, record-id: record-id })
)

(define-read-only (get-vehicle-maintenance-count (vin (string-ascii 17)))
  (match (map-get? vehicle-maintenance-count { vin: vin })
    count-data (some (get count count-data))
    none
  )
)

(define-read-only (get-mechanic-info (mechanic principal))
  (map-get? certified-mechanics { mechanic: mechanic })
)

(define-read-only (get-mechanic-reputation (mechanic principal))
  (map-get? mechanic-reputation { mechanic: mechanic })
)

(define-read-only (get-service-category (category (string-ascii 50)))
  (map-get? service-categories { category: category })
)

(define-read-only (calculate-average-rating (mechanic principal))
  (match (map-get? mechanic-reputation { mechanic: mechanic })
    rep-data 
      (if (> (get rating-count rep-data) u0)
        (some (/ (get rating-sum rep-data) (get rating-count rep-data)))
        none
      )
    none
  )
)

(define-read-only (is-record-verified (vin (string-ascii 17)) (record-id uint))
  (match (map-get? maintenance-records { vin: vin, record-id: record-id })
    record-data (get verified record-data)
    false
  )
)

(define-read-only (get-next-service-due (vin (string-ascii 17)) (record-id uint))
  (match (map-get? maintenance-records { vin: vin, record-id: record-id })
    record-data (get next-service-due record-data)
    none
  )
)
