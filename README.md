# sui_nft_rental

### Example Use Case #1: Description

Enable users to rent NFTs.

### Example Use Case #1: Requirements

- Enable a lender to offer their assets for renting for a specified period of time (List for renting)
- Enable a lender to define custom rules for return policies.
    - Borrower has to comply with minimum renting periods and should be able to cancel the rental by paying a penalty.
- Borrower can gain mutable or immutable access to the NFT.
    - Immutable access is read only, no further checks
    - Mutable, the lender should consider downgrade and upgrade operations and include them in the renting fee.
- After the renting period has finished the item can be sold normally.