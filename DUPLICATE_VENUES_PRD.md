# Duplicate Venues Problem - Product Requirements Document

## Executive Summary

The Trivia Advisor platform needs a streamlined solution to manage duplicate venue records. The focus is on simple criteria to prevent new duplicates and provide an easy interface for reviewing existing ones.

## Solution Strategy

### 1. Prevention of New Duplicates

#### Database Constraints
- **Unique Constraint on Name + Postcode**  
  Prevent duplicate entries by enforcing a unique constraint on the combination of venue name and postcode.

#### Application Logic
- **Fuzzy Name Matching with Address Comparison**  
  Use a shared fuzzy matching logic to detect potential duplicates based on:
  - Name similarity (e.g., >85%)
  - Normalized address and postcode comparison

- **Staged Rollout of Fuzzy Duplicate Logic**
  - **Phase 1:** Integrate the fuzzy matching logic into the upcoming duplicate review interface to validate its accuracy and tune confidence thresholds
  - **Phase 2:** Once verified, extend the logic to block or flag new venue creation (e.g. in scrapers or admin UI)
  - This ensures the detection logic is battle-tested in a review setting before enforcing constraints on incoming data

### 2. Management of Existing Duplicates

#### Review Interface
- **Dedicated Duplicate Review Page**
  - Lists suspected duplicates based on:
    - Exact name + postcode
    - High name similarity + same city or postcode
    - Same Google Place ID
  - Provides tools to:
    - Manually confirm/merge duplicates
    - Review venue details (creation date, event count, address, etc.)
    - Reject false positives

#### Safe Merge Tools
- Migrate associated events
- Combine metadata (prefer newer data or higher quality images)
- Soft-delete or archive duplicates (with rollback support)
- Log all merge actions for auditing

## Success Metrics
- 90%+ reduction in duplicate venues
- <1% false positive rate for merges
- No loss of associated event data
- Improved venue search relevance and user experience
