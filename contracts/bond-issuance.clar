;; Bond Issuance Verification Contract
;; Validates municipal bond offerings and tracks investor participation

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-BOND-NOT-FOUND (err u101))
(define-constant ERR-BOND-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-AMOUNT (err u103))
(define-constant ERR-INVALID-RATE (err u104))
(define-constant ERR-BOND-NOT-ACTIVE (err u105))
(define-constant ERR-INSUFFICIENT-INVESTMENT (err u106))

;; Data Variables
(define-data-var next-bond-id uint u1)
(define-data-var contract-active bool true)

;; Data Maps
(define-map bonds
  { bond-id: uint }
  {
    issuer: principal,
    amount: uint,
    interest-rate: uint,
    maturity-date: uint,
    issue-date: uint,
    status: (string-ascii 20),
    total-raised: uint,
    investor-count: uint
  }
)

(define-map bond-investors
  { bond-id: uint, investor: principal }
  {
    investment-amount: uint,
    investment-date: uint,
    status: (string-ascii 20)
  }
)

(define-map issuer-bonds
  { issuer: principal }
  { bond-ids: (list 100 uint) }
)

;; Read-only functions
(define-read-only (get-bond (bond-id uint))
  (map-get? bonds { bond-id: bond-id })
)

(define-read-only (get-investor-position (bond-id uint) (investor principal))
  (map-get? bond-investors { bond-id: bond-id, investor: investor })
)

(define-read-only (get-issuer-bonds (issuer principal))
  (default-to { bond-ids: (list) } (map-get? issuer-bonds { issuer: issuer }))
)

(define-read-only (get-next-bond-id)
  (var-get next-bond-id)
)

(define-read-only (is-contract-active)
  (var-get contract-active)
)

;; Private functions
(define-private (is-authorized (caller principal))
  (or (is-eq caller CONTRACT-OWNER) (is-eq caller tx-sender))
)

(define-private (add-bond-to-issuer (issuer principal) (bond-id uint))
  (let ((current-bonds (get bond-ids (get-issuer-bonds issuer))))
    (map-set issuer-bonds
      { issuer: issuer }
      { bond-ids: (unwrap! (as-max-len? (append current-bonds bond-id) u100) false) }
    )
  )
)

;; Public functions
(define-public (issue-bond (amount uint) (interest-rate uint) (maturity-date uint))
  (let ((bond-id (var-get next-bond-id)))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (and (> interest-rate u0) (<= interest-rate u2000)) ERR-INVALID-RATE)
    (asserts! (> maturity-date block-height) ERR-INVALID-AMOUNT)

    (map-set bonds
      { bond-id: bond-id }
      {
        issuer: tx-sender,
        amount: amount,
        interest-rate: interest-rate,
        maturity-date: maturity-date,
        issue-date: block-height,
        status: "active",
        total-raised: u0,
        investor-count: u0
      }
    )

    (add-bond-to-issuer tx-sender bond-id)
    (var-set next-bond-id (+ bond-id u1))
    (ok bond-id)
  )
)

(define-public (invest-in-bond (bond-id uint) (investment-amount uint))
  (let ((bond-data (unwrap! (get-bond bond-id) ERR-BOND-NOT-FOUND)))
    (asserts! (var-get contract-active) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status bond-data) "active") ERR-BOND-NOT-ACTIVE)
    (asserts! (> investment-amount u0) ERR-INSUFFICIENT-INVESTMENT)
    (asserts! (<= (+ (get total-raised bond-data) investment-amount) (get amount bond-data)) ERR-INVALID-AMOUNT)

    (map-set bond-investors
      { bond-id: bond-id, investor: tx-sender }
      {
        investment-amount: investment-amount,
        investment-date: block-height,
        status: "active"
      }
    )

    (map-set bonds
      { bond-id: bond-id }
      (merge bond-data {
        total-raised: (+ (get total-raised bond-data) investment-amount),
        investor-count: (+ (get investor-count bond-data) u1)
      })
    )

    (ok true)
  )
)

(define-public (update-bond-status (bond-id uint) (new-status (string-ascii 20)))
  (let ((bond-data (unwrap! (get-bond bond-id) ERR-BOND-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get issuer bond-data) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set bonds
      { bond-id: bond-id }
      (merge bond-data { status: new-status })
    )
    (ok true)
  )
)

(define-public (set-contract-active (active bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (var-set contract-active active)
    (ok true)
  )
)
