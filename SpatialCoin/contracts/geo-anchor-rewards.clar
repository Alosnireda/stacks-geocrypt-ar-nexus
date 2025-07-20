;; GeoCrypt AR Treasure Protocol - Main Contract
;; geo-anchor-rewards.clar
;; A location-based AR treasure hunting platform with crypto rewards

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ANCHOR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-COORDINATES (err u102))
(define-constant ERR-INSUFFICIENT-STAKE (err u103))
(define-constant ERR-ALREADY-CLAIMED (err u104))
(define-constant ERR-TOO-FAR-FROM-ANCHOR (err u105))
(define-constant ERR-COOLDOWN-ACTIVE (err u106))
(define-constant ERR-CAMPAIGN-NOT-FOUND (err u107))
(define-constant ERR-CAMPAIGN-ENDED (err u108))
(define-constant ERR-INVALID-PROOF (err u109))
(define-constant ERR-ANCHOR-DENSITY-EXCEEDED (err u110))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-STAKE-AMOUNT u1000) ;; 1000 SPATIAL tokens minimum
(define-constant PROXIMITY-THRESHOLD u50) ;; 50 meters in micro-degrees
(define-constant CLAIM-COOLDOWN u144) ;; ~24 hours in blocks
(define-constant MAX-ANCHORS-PER-AREA u10) ;; Max 10 anchors per 1km radius
(define-constant COMMISSION-RATE u10) ;; 10% commission to anchor creator

;; Data structures
(define-map anchors
  { anchor-id: uint }
  {
    creator: principal,
    latitude: int,
    longitude: int,
    reward-pool: uint,
    metadata-uri: (string-ascii 256),
    rarity-tier: uint, ;; 1=Common, 2=Rare, 3=Epic, 4=Legendary
    created-at: uint,
    total-claims: uint,
    is-active: bool,
    stake-amount: uint
  }
)

(define-map treasure-hunters
  { hunter: principal }
  {
    total-discoveries: uint,
    total-rewards: uint,
    last-claim-block: uint,
    reputation-score: uint,
    is-verified: bool
  }
)

(define-map anchor-claims
  { anchor-id: uint, hunter: principal }
  {
    claimed-at: uint,
    reward-amount: uint,
    gps-proof-hash: (buff 32)
  }
)

(define-map treasure-campaigns
  { campaign-id: uint }
  {
    creator: principal,
    name: (string-ascii 64),
    anchor-ids: (list 50 uint),
    total-reward-pool: uint,
    start-block: uint,
    end-block: uint,
    min-discoveries: uint,
    bonus-multiplier: uint,
    is-active: bool
  }
)

(define-map campaign-progress
  { campaign-id: uint, hunter: principal }
  {
    discoveries-count: uint,
    total-earned: uint,
    completed-at: (optional uint)
  }
)

(define-map area-density
  { lat-zone: int, lon-zone: int } ;; Zones are 1km x 1km grid squares
  {
    anchor-count: uint,
    last-updated: uint
  }
)

;; Data variables
(define-data-var next-anchor-id uint u1)
(define-data-var next-campaign-id uint u1)
(define-data-var total-anchors uint u0)
(define-data-var total-rewards-distributed uint u0)
(define-data-var platform-fee-rate uint u5) ;; 5% platform fee

;; Utility functions
(define-private (get-zone-coords (latitude int) (longitude int))
  {
    lat-zone: (/ latitude 1000000), ;; Convert to 1km zones
    lon-zone: (/ longitude 1000000)
  }
)

(define-private (calculate-distance (lat1 int) (lon1 int) (lat2 int) (lon2 int))
  ;; Simplified distance calculation in micro-degrees
  ;; For production, implement proper Haversine formula
  (let (
    (lat-diff (if (> lat1 lat2) (- lat1 lat2) (- lat2 lat1)))
    (lon-diff (if (> lon1 lon2) (- lon1 lon2) (- lon2 lon1)))
  )
    (to-uint (+ (* lat-diff lat-diff) (* lon-diff lon-diff)))
  )
)

(define-private (is-within-proximity (anchor-lat int) (anchor-lon int) (proof-lat int) (proof-lon int))
  (let ((distance-squared (calculate-distance anchor-lat anchor-lon proof-lat proof-lon)))
    (<= distance-squared (* PROXIMITY-THRESHOLD PROXIMITY-THRESHOLD))
  )
)

(define-private (calculate-rarity-bonus (rarity-tier uint))
  (if (is-eq rarity-tier u1) u100      ;; Common: 100%
    (if (is-eq rarity-tier u2) u150    ;; Rare: 150%
      (if (is-eq rarity-tier u3) u250  ;; Epic: 250%
        u500                           ;; Legendary: 500%
      )
    )
  )
)

;; Public functions

;; Register as a treasure hunter
(define-public (register-hunter)
  (let ((existing-hunter (map-get? treasure-hunters { hunter: tx-sender })))
    (if (is-none existing-hunter)
      (ok (map-set treasure-hunters
        { hunter: tx-sender }
        {
          total-discoveries: u0,
          total-rewards: u0,
          last-claim-block: u0,
          reputation-score: u100,
          is-verified: false
        }
      ))
      (ok true) ;; Already registered
    )
  )
)

;; Create a new AR treasure anchor
(define-public (create-anchor 
  (latitude int) 
  (longitude int) 
  (reward-pool uint)
  (metadata-uri (string-ascii 256))
  (rarity-tier uint)
  (stake-amount uint)
)
  (let (
    (anchor-id (var-get next-anchor-id))
    (zone-coords (get-zone-coords latitude longitude))
    (current-density (default-to { anchor-count: u0, last-updated: u0 } 
                      (map-get? area-density zone-coords)))
  )
    (if (and
      ;; Validate coordinates (Earth bounds in micro-degrees)
      (>= latitude -90000000) (<= latitude 90000000)
      (>= longitude -180000000) (<= longitude 180000000)
      ;; Validate stake amount
      (>= stake-amount MIN-STAKE-AMOUNT)
      ;; Validate rarity tier
      (and (>= rarity-tier u1) (<= rarity-tier u4))
      ;; Check area density limits
      (< (get anchor-count current-density) MAX-ANCHORS-PER-AREA)
      ;; Validate reward pool
      (> reward-pool u0)
    )
      (begin
        ;; Create the anchor
        (map-set anchors
          { anchor-id: anchor-id }
          {
            creator: tx-sender,
            latitude: latitude,
            longitude: longitude,
            reward-pool: reward-pool,
            metadata-uri: metadata-uri,
            rarity-tier: rarity-tier,
            created-at: block-height,
            total-claims: u0,
            is-active: true,
            stake-amount: stake-amount
          }
        )
        ;; Update area density
        (map-set area-density zone-coords
          {
            anchor-count: (+ (get anchor-count current-density) u1),
            last-updated: block-height
          }
        )
        ;; Update global counters
        (var-set next-anchor-id (+ anchor-id u1))
        (var-set total-anchors (+ (var-get total-anchors) u1))
        ;; TODO: Transfer stake amount to contract (implement with SpatialCoin contract)
        (ok anchor-id)
      )
      (if (>= (get anchor-count current-density) MAX-ANCHORS-PER-AREA)
        ERR-ANCHOR-DENSITY-EXCEEDED
        (if (< stake-amount MIN-STAKE-AMOUNT)
          ERR-INSUFFICIENT-STAKE
          ERR-INVALID-COORDINATES
        )
      )
    )
  )
)

;; Claim treasure reward by proving proximity
(define-public (claim-treasure-reward 
  (anchor-id uint) 
  (proof-latitude int) 
  (proof-longitude int)
  (gps-proof-hash (buff 32))
)
  (let (
    (anchor-data (unwrap! (map-get? anchors { anchor-id: anchor-id }) ERR-ANCHOR-NOT-FOUND))
    (hunter-data (unwrap! (map-get? treasure-hunters { hunter: tx-sender }) ERR-NOT-AUTHORIZED))
    (existing-claim (map-get? anchor-claims { anchor-id: anchor-id, hunter: tx-sender }))
  )
    (if (and
      ;; Check if anchor is active
      (get is-active anchor-data)
      ;; Check if hunter hasn't already claimed this anchor
      (is-none existing-claim)
      ;; Check cooldown period
      (>= block-height (+ (get last-claim-block hunter-data) CLAIM-COOLDOWN))
      ;; Verify proximity
      (is-within-proximity 
        (get latitude anchor-data) 
        (get longitude anchor-data) 
        proof-latitude 
        proof-longitude)
    )
      (let (
        (base-reward (get reward-pool anchor-data))
        (rarity-bonus (calculate-rarity-bonus (get rarity-tier anchor-data)))
        (final-reward (/ (* base-reward rarity-bonus) u100))
        (creator-commission (/ (* final-reward COMMISSION-RATE) u100))
        (hunter-reward (- final-reward creator-commission))
        (platform-fee (/ (* final-reward (var-get platform-fee-rate)) u100))
        (net-reward (- hunter-reward platform-fee))
      )
        (begin
          ;; Record the claim
          (map-set anchor-claims
            { anchor-id: anchor-id, hunter: tx-sender }
            {
              claimed-at: block-height,
              reward-amount: net-reward,
              gps-proof-hash: gps-proof-hash
            }
          )
          ;; Update hunter stats
          (map-set treasure-hunters
            { hunter: tx-sender }
            (merge hunter-data {
              total-discoveries: (+ (get total-discoveries hunter-data) u1),
              total-rewards: (+ (get total-rewards hunter-data) net-reward),
              last-claim-block: block-height,
              reputation-score: (+ (get reputation-score hunter-data) u10)
            })
          )
          ;; Update anchor stats
          (map-set anchors
            { anchor-id: anchor-id }
            (merge anchor-data {
              total-claims: (+ (get total-claims anchor-data) u1)
            })
          )
          ;; Update global stats
          (var-set total-rewards-distributed 
            (+ (var-get total-rewards-distributed) net-reward))
          ;; TODO: Transfer rewards to hunter and commission to creator
          (ok net-reward)
        )
      )
      (if (is-some existing-claim)
        ERR-ALREADY-CLAIMED
        (if (< block-height (+ (get last-claim-block hunter-data) CLAIM-COOLDOWN))
          ERR-COOLDOWN-ACTIVE
          ERR-TOO-FAR-FROM-ANCHOR
        )
      )
    )
  )
)

;; Create a treasure hunt campaign
(define-public (create-treasure-campaign
  (name (string-ascii 64))
  (anchor-ids (list 50 uint))
  (total-reward-pool uint)
  (duration-blocks uint)
  (min-discoveries uint)
  (bonus-multiplier uint)
)
  (let ((campaign-id (var-get next-campaign-id)))
    (if (and
      (> (len anchor-ids) u0)
      (> total-reward-pool u0)
      (> duration-blocks u0)
      (> bonus-multiplier u0)
    )
      (begin
        (map-set treasure-campaigns
          { campaign-id: campaign-id }
          {
            creator: tx-sender,
            name: name,
            anchor-ids: anchor-ids,
            total-reward-pool: total-reward-pool,
            start-block: block-height,
            end-block: (+ block-height duration-blocks),
            min-discoveries: min-discoveries,
            bonus-multiplier: bonus-multiplier,
            is-active: true
          }
        )
        (var-set next-campaign-id (+ campaign-id u1))
        (ok campaign-id)
      )
      ERR-INVALID-COORDINATES ;; Reusing error for invalid params
    )
  )
)

;; Read-only functions
(define-read-only (get-anchor (anchor-id uint))
  (map-get? anchors { anchor-id: anchor-id })
)

(define-read-only (get-hunter-profile (hunter principal))
  (map-get? treasure-hunters { hunter: hunter })
)

(define-read-only (get-campaign (campaign-id uint))
  (map-get? treasure-campaigns { campaign-id: campaign-id })
)

(define-read-only (has-claimed-anchor (anchor-id uint) (hunter principal))
  (is-some (map-get? anchor-claims { anchor-id: anchor-id, hunter: hunter }))
)

(define-read-only (get-area-density (latitude int) (longitude int))
  (let ((zone-coords (get-zone-coords latitude longitude)))
    (map-get? area-density zone-coords)
  )
)

(define-read-only (get-platform-stats)
  {
    total-anchors: (var-get total-anchors),
    total-rewards-distributed: (var-get total-rewards-distributed),
    next-anchor-id: (var-get next-anchor-id),
    platform-fee-rate: (var-get platform-fee-rate)
  }
)