# Contract Delta — WI-008

## Endpoint

`GET /cashier/order/today`

## Before

- Optional: `shopId`, `transac_status`, `date`.
- Default and `date` queries returned an operational 24-hour window under base `cashier:operate` permission.

## After

- Adds optional `startTime`, `endTime`.
- Default: current-shop `unsettled` orders plus orders created within the last 3 hours.
- Any explicit time selection (`date` or range) additionally requires `admin:super`.
- Range parameters must be paired, cannot mix with `date`, and may span at most 31 days.
- Response body remains `R` with `list`.

## Compatibility

Request/response schema change is additive, but default filtering and `date` authorization are intentional behavioral restrictions. Ordinary clients need no changes; super-admin clients may add a range picker in a separate UI Work Item.

## Consumer handoff

- Gate time controls on permission `admin:super`.
- Send local time in `yyyy-MM-dd HH:mm:ss` (ISO `T` also accepted).
- Handle 400 validation and 403 elevated-permission responses.
