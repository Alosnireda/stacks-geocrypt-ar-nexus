;; SpatialCoin Token Contract
;; spatial-coin-token.clar
;; SIP-010 compliant fungible token for GeoCrypt AR Treasure Protocol

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INSUFFICIENT-BALANCE (err u401))
(define-constant ERR-INVALID-AMOUNT (err u402))
(define-constant ERR-INVALID-RECIPIENT (err u403))
(define-constant ERR-TOKEN-NOT-LAUNCHED (err u404))
(define-constant ERR-ALREADY-LAUNCHED (err u405))
(define-constant ERR-MINT-LIMIT-EXCEEDED (err u406))
(define-constant ERR-BURN-FAILED (err u407))
(define-constant ERR-STAKING-FAILED (err u408))
(define-constant ERR-UNSTAKING-FAILED (err u409))
(define-constant ERR-INVALID-LOCK-PERIOD (err u410))

;; Token constants
(define-constant TOKEN-NAME "SpatialCoin")
(define-constant TOKEN-SYMBOL "SPATIAL")
(define-constant TOKEN-DECIMALS u6)
(define-constant TOKEN-MAX-SUPPLY u100000000000000) ;; 100M SPATIAL with 6 decimals
(define-constant INITIAL-SUPPLY u40000000000000)    ;; 40M SPATIAL for treasure rewards
(define-constant MIN-TRANSFER-AMOUNT u1)            ;; Minimum 0.000001 SPATIAL
(define-constant BURN-FEE-RATE u50)                 ;; 0.5% burn fee on transfers

;; Contract owner and governance
(define-constant CONTRACT-OWNER tx-sender)
(define-constant TREASURY-WALLET tx-sender) ;; Will be set to proper treasury on deployment

;; Data variables
(define-data-var token-launched bool false)
(define-data-var total-supply uint u0)
(define-data-var total-staked uint u0)
(define-data-var total-burned uint u0)
(define-data-var is-transfers-enabled bool true)
(define-data-var reward-pool-balance uint u0)

;; Maps for balances and allowances (SIP-010 standard)
(define-map token-balances principal uint)
(define-map token-allowances { owner: principal, spender: principal } uint)

;; Staking and rewards maps
(define-map staking-positions
  { staker: principal }
  {
    amount: uint,
    locked-until: uint,
    reward-debt: uint,
    created-at: uint
  }
)

(define-map anchor-stakes
  { anchor-creator: principal, anchor-id: uint }
  {
    staked-amount: uint,
    locked-until: uint,
    slashed: bool
  }
)

(define-map reward-claims
  { claimer: principal, claim-id: uint }
  {
    amount: uint,
    claimed-at: uint,
    anchor-id: (optional uint),
    claim-type: (string-ascii 32) ;; "treasure", "staking", "campaign"
  }
)

;; Data tracking
(define-data-var next-claim-id uint u1)
(define-data-var staking-reward-rate uint u1000) ;; 10% APR (1000 basis points)

;; Private utility functions
(define-private (is-valid-amount (amount uint))
  (and (> amount u0) (<= amount TOKEN-MAX-SUPPLY))
)

(define-private (is-valid-principal (user principal))
  (not (is-eq user (as-contract tx-sender)))
)

(define-private (calculate-burn-fee (amount uint))
  (/ (* amount BURN-FEE-RATE) u10000)
)

(define-private (calculate-staking-rewards (amount uint) (duration uint))
  ;; Simple APR calculation: (amount * rate * duration) / (365 * 144 * 10000)
  ;; Assuming ~144 blocks per day
  (/ (* (* amount (var-get staking-reward-rate)) duration) u525600000)
)

;; SIP-010 Standard Functions

;; Get token name
(define-read-only (get-name)
  (ok TOKEN-NAME)
)

;; Get token symbol  
(define-read-only (get-symbol)
  (ok TOKEN-SYMBOL)
)

;; Get token decimals
(define-read-only (get-decimals)
  (ok TOKEN-DECIMALS)
)

;; Get total supply
(define-read-only (get-total-supply)
  (ok (var-get total-supply))
)

;; Get token URI (metadata)
(define-read-only (get-token-uri)
  (ok (some "https://ipfs.io/ipfs/QmSpatialCoinMetadata"))
)

;; Get balance of a principal
(define-read-only (get-balance (who principal))
  (ok (default-to u0 (map-get? token-balances who)))
)

;; Transfer function (SIP-010 compliant)
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
  (if (and 
    (var-get token-launched)
    (var-get is-transfers-enabled)
    (is-valid-amount amount)
    (>= amount MIN-TRANSFER-AMOUNT)
    (is-valid-principal recipient)
    (is-eq tx-sender sender)
  )
    (let (
      (sender-balance (unwrap! (get-balance sender) ERR-INSUFFICIENT-BALANCE))
      (burn-fee (calculate-burn-fee amount))
      (net-amount (- amount burn-fee))
    )
      (if (>= sender-balance amount)
        (begin
          ;; Update sender balance
          (map-set token-balances sender (- sender-balance amount))
          ;; Update recipient balance  
          (map-set token-balances recipient 
            (+ (unwrap! (get-balance recipient) ERR-INSUFFICIENT-BALANCE) net-amount))
          ;; Burn the fee
          (var-set total-supply (- (var-get total-supply) burn-fee))
          (var-set total-burned (+ (var-get total-burned) burn-fee))
          ;; Emit transfer event
          (print {
            event: "transfer",
            sender: sender,
            recipient: recipient,
            amount: net-amount,
            burn-fee: burn-fee,
            memo: memo
          })
          (ok true)
        )
        ERR-INSUFFICIENT-BALANCE
      )
    )
    ERR-INVALID-AMOUNT
  )
)

;; Get allowance
(define-read-only (get-allowance (owner principal) (spender principal))
  (ok (default-to u0 (map-get? token-allowances { owner: owner, spender: spender })))
)

;; Approve spending allowance
(define-public (approve (spender principal) (amount uint))
  (if (and 
    (is-valid-principal spender)
    (not (is-eq tx-sender spender))
  )
    (begin
      (map-set token-allowances 
        { owner: tx-sender, spender: spender } 
        amount)
      (print {
        event: "approve",
        owner: tx-sender,
        spender: spender,
        amount: amount
      })
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

;; Transfer from allowance
(define-public (transfer-from (amount uint) (owner principal) (recipient principal) (memo (optional (buff 34))))
  (let (
    (current-allowance (unwrap! (get-allowance owner tx-sender) ERR-NOT-AUTHORIZED))
  )
    (if (>= current-allowance amount)
      (begin
        ;; Reduce allowance
        (map-set token-allowances 
          { owner: owner, spender: tx-sender }
          (- current-allowance amount))
        ;; Execute transfer
        (transfer amount owner recipient memo)
      )
      ERR-NOT-AUTHORIZED
    )
  )
)

;; Token launch and minting functions

;; Launch the token (only owner)
(define-public (launch-token)
  (if (and 
    (is-eq tx-sender CONTRACT-OWNER)
    (not (var-get token-launched))
  )
    (begin
      ;; Mint initial supply to treasury
      (map-set token-balances TREASURY-WALLET INITIAL-SUPPLY)
      (var-set total-supply INITIAL-SUPPLY)
      (var-set reward-pool-balance INITIAL-SUPPLY)
      (var-set token-launched true)
      (print {
        event: "token-launched",
        initial-supply: INITIAL-SUPPLY,
        treasury: TREASURY-WALLET
      })
      (ok true)
    )
    (if (var-get token-launched)
      ERR-ALREADY-LAUNCHED
      ERR-NOT-AUTHORIZED
    )
  )
)

;; Mint tokens for specific purposes (only authorized contracts)
(define-public (mint (amount uint) (recipient principal) (purpose (string-ascii 32)))
  (if (and
    (var-get token-launched)
    (is-valid-amount amount)
    (is-valid-principal recipient)
    (<= (+ (var-get total-supply) amount) TOKEN-MAX-SUPPLY)
    ;; Only specific contracts can mint (geo-anchor-rewards, etc.)
    (or (is-eq tx-sender CONTRACT-OWNER)
        (is-eq contract-caller .geo-anchor-rewards))
  )
    (begin
      (map-set token-balances recipient 
        (+ (unwrap! (get-balance recipient) ERR-INSUFFICIENT-BALANCE) amount))
      (var-set total-supply (+ (var-get total-supply) amount))
      (print {
        event: "mint",
        recipient: recipient,
        amount: amount,
        purpose: purpose
      })
      (ok true)
    )
    ERR-MINT-LIMIT-EXCEEDED
  )
)

;; Burn tokens
(define-public (burn (amount uint))
  (let (
    (sender-balance (unwrap! (get-balance tx-sender) ERR-INSUFFICIENT-BALANCE))
  )
    (if (and
      (is-valid-amount amount)
      (>= sender-balance amount)
    )
      (begin
        (map-set token-balances tx-sender (- sender-balance amount))
        (var-set total-supply (- (var-get total-supply) amount))
        (var-set total-burned (+ (var-get total-burned) amount))
        (print {
          event: "burn",
          burner: tx-sender,
          amount: amount
        })
        (ok true)
      )
      ERR-BURN-FAILED
    )
  )
)

;; Staking functions

;; Stake tokens with lock period
(define-public (stake-tokens (amount uint) (lock-blocks uint))
  (let (
    (user-balance (unwrap! (get-balance tx-sender) ERR-INSUFFICIENT-BALANCE))
    (existing-stake (map-get? staking-positions { staker: tx-sender }))
  )
    (if (and
      (is-valid-amount amount)
      (>= user-balance amount)
      (> lock-blocks u0)
      (<= lock-blocks u52560) ;; Max 1 year lock (~365 days * 144 blocks)
    )
      (begin
        ;; Transfer tokens to staking (burn from circulation)
        (map-set token-balances tx-sender (- user-balance amount))
        ;; Create or update staking position
        (map-set staking-positions
          { staker: tx-sender }
          (match existing-stake
            current-stake
            {
              amount: (+ (get amount current-stake) amount),
              locked-until: (+ block-height lock-blocks),
              reward-debt: (get reward-debt current-stake),
              created-at: (get created-at current-stake)
            }
            {
              amount: amount,
              locked-until: (+ block-height lock-blocks),
              reward-debt: u0,
              created-at: block-height
            }
          )
        )
        (var-set total-staked (+ (var-get total-staked) amount))
        (print {
          event: "stake",
          staker: tx-sender,
          amount: amount,
          locked-until: (+ block-height lock-blocks)
        })
        (ok true)
      )
      ERR-STAKING-FAILED
    )
  )
)

;; Unstake tokens (after lock period)
(define-public (unstake-tokens (amount uint))
  (let (
    (stake-position (unwrap! (map-get? staking-positions { staker: tx-sender }) ERR-STAKING-FAILED))
    (staked-amount (get amount stake-position))
    (locked-until (get locked-until stake-position))
  )
    (if (and
      (>= block-height locked-until)
      (>= staked-amount amount)
      (> amount u0)
    )
      (let (
        (rewards (calculate-staking-rewards amount (- block-height (get created-at stake-position))))
        (total-return (+ amount rewards))
      )
        (begin
          ;; Update staking position
          (if (is-eq staked-amount amount)
            ;; Remove position if fully unstaking
            (map-delete staking-positions { staker: tx-sender })
            ;; Update position with remaining amount
            (map-set staking-positions
              { staker: tx-sender }
              (merge stake-position { amount: (- staked-amount amount) })
            )
          )
          ;; Return tokens plus rewards to user
          (map-set token-balances tx-sender 
            (+ (unwrap! (get-balance tx-sender) ERR-INSUFFICIENT-BALANCE) total-return))
          ;; Update global counters
          (var-set total-staked (- (var-get total-staked) amount))
          (var-set total-supply (+ (var-get total-supply) rewards)) ;; Mint rewards
          (print {
            event: "unstake",
            staker: tx-sender,
            amount: amount,
            rewards: rewards,
            total-return: total-return
          })
          (ok total-return)
        )
      )
      ERR-UNSTAKING-FAILED
    )
  )
)

;; Anchor staking for GeoCrypt protocol
(define-public (stake-for-anchor (anchor-creator principal) (anchor-id uint) (amount uint) (lock-blocks uint))
  (if (and
    (is-eq contract-caller .geo-anchor-rewards) ;; Only geo-anchor-rewards can call
    (is-valid-amount amount)
    (>= (unwrap! (get-balance anchor-creator) ERR-INSUFFICIENT-BALANCE) amount)
  )
    (begin
      ;; Transfer stake from creator
      (map-set token-balances anchor-creator 
        (- (unwrap! (get-balance anchor-creator) ERR-INSUFFICIENT-BALANCE) amount))
      ;; Record anchor stake
      (map-set anchor-stakes
        { anchor-creator: anchor-creator, anchor-id: anchor-id }
        {
          staked-amount: amount,
          locked-until: (+ block-height lock-blocks),
          slashed: false
        }
      )
      (var-set total-staked (+ (var-get total-staked) amount))
      (ok true)
    )
    ERR-STAKING-FAILED
  )
)

;; Reward distribution for treasure hunters
(define-public (distribute-treasure-reward (hunter principal) (amount uint) (anchor-id uint))
  (if (and
    (is-eq contract-caller .geo-anchor-rewards) ;; Only geo-anchor-rewards can call
    (is-valid-amount amount)
    (>= (var-get reward-pool-balance) amount)
  )
    (let (
      (claim-id (var-get next-claim-id))
    )
      (begin
        ;; Transfer reward to hunter
        (map-set token-balances hunter 
          (+ (unwrap! (get-balance hunter) ERR-INSUFFICIENT-BALANCE) amount))
        ;; Record reward claim
        (map-set reward-claims
          { claimer: hunter, claim-id: claim-id }
          {
            amount: amount,
            claimed-at: block-height,
            anchor-id: (some anchor-id),
            claim-type: "treasure"
          }
        )
        ;; Update counters
        (var-set reward-pool-balance (- (var-get reward-pool-balance) amount))
        (var-set next-claim-id (+ claim-id u1))
        (print {
          event: "treasure-reward",
          hunter: hunter,
          amount: amount,
          anchor-id: anchor-id,
          claim-id: claim-id
        })
        (ok claim-id)
      )
    )
    ERR-INSUFFICIENT-BALANCE
  )
)

;; Read-only functions for additional data

(define-read-only (get-staking-position (staker principal))
  (map-get? staking-positions { staker: staker })
)

(define-read-only (get-anchor-stake (anchor-creator principal) (anchor-id uint))
  (map-get? anchor-stakes { anchor-creator: anchor-creator, anchor-id: anchor-id })
)

(define-read-only (get-reward-claim (claimer principal) (claim-id uint))
  (map-get? reward-claims { claimer: claimer, claim-id: claim-id })
)

(define-read-only (get-token-stats)
  {
    total-supply: (var-get total-supply),
    total-staked: (var-get total-staked),
    total-burned: (var-get total-burned),
    reward-pool-balance: (var-get reward-pool-balance),
    circulating-supply: (- (var-get total-supply) (var-get total-staked)),
    is-launched: (var-get token-launched),
    transfers-enabled: (var-get is-transfers-enabled)
  }
)

(define-read-only (calculate-staking-apy (amount uint) (lock-duration uint))
  (calculate-staking-rewards amount lock-duration)
)

;; Admin functions (contract owner only)

(define-public (set-transfers-enabled (enabled bool))
  (if (is-eq tx-sender CONTRACT-OWNER)
    (begin
      (var-set is-transfers-enabled enabled)
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (update-staking-reward-rate (new-rate uint))
  (if (and 
    (is-eq tx-sender CONTRACT-OWNER)
    (<= new-rate u5000) ;; Max 50% APR
  )
    (begin
      (var-set staking-reward-rate new-rate)
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)

(define-public (emergency-pause)
  (if (is-eq tx-sender CONTRACT-OWNER)
    (begin
      (var-set is-transfers-enabled false)
      (print { event: "emergency-pause", block: block-height })
      (ok true)
    )
    ERR-NOT-AUTHORIZED
  )
)