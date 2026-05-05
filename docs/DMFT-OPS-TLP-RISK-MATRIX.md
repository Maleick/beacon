# DMFT Operations: TLP Server GM Enforcement Risk Matrix

> **Status:** Research-based draft — pending SME validation from Matt / Blownt  
> **Scope:** Automation risk surface for DMFT (Dungeon Master Farming Tool) sustained autonomous operation on EverQuest TLP servers  
> **Last Updated:** 2025-05-05  
> **Issue:** AutoShip #342

---

## 1. Executive Summary

TLP (Time-Locked Progression) servers exhibit **higher GM enforcement activity** than live servers, but enforcement is **sporadic and unpredictable**. DMFT autonomous operation carries elevated risk on TLP compared to live, particularly during expansion launches, seasonal events, and peak hours. This matrix quantifies known risk factors and proposes mitigation tiers.

---

## 2. Risk Matrix

| Risk Factor | Severity (1-5) | Likelihood | Impact | Mitigation Tier |
|-------------|---------------|------------|--------|-----------------|
| **Mass ban waves tied to expansion launches** | 4 | Medium | Account loss + gear reset | **Tier 1: Pause automation 48-72h post-launch** |
| **Peak-hour GM patrols (6pm-11pm server time)** | 3 | High | Suspension (7-30 days) | **Tier 2: Restrict to off-peak only (1am-6am)** |
| **Boxing in full group (6 chars) vs solo farming** | 4 | High | Ban (permanent) | **Tier 2: Limit to 2-box max; avoid 6-box patterns** |
| **Third-party tool detection (MQ, ISBoxer, etc.)** | 5 | Medium | Permanent ban | **Tier 1: No injected tools; use only DMFT-native input** |
| **Report-driven GM response (player reports)** | 3 | High | Suspension | **Tier 2: Rotate zones; avoid over-farmed camps** |
| **Automated tell/response failure** | 4 | Medium | Ban | **Tier 1: Human-in-the-loop tell response** |
| **Seasonal event GM sweeps (anniversary, holidays)** | 3 | Medium | Suspension | **Tier 2: Reduce hours 50% during events** |
| **Progression server unlock phases (Classic → Kunark, etc.)** | 4 | High | Account loss | **Tier 1: Full pause 24h around unlock** |
| **AFK farming / unattended combat** | 5 | High | Permanent ban | **Tier 1: Active monitoring required; no AFK loops** |

### Risk Score Formula
```
Risk Score = Severity × Likelihood × (1 if no mitigation, 0.5 if Tier 2, 0.2 if Tier 1)
```

| Tier | Description | Trigger |
|------|-------------|---------|
| **Tier 1 (Critical)** | Full pause or human-in-the-loop required | Expansion launch, unlock phases, tool detection risk, AFK farming |
| **Tier 2 (Elevated)** | Restricted hours, reduced box count, zone rotation | Peak hours, seasonal events, player reports |
| **Tier 3 (Normal)** | Standard DMFT operation with logging | Off-peak, stable content phases, low-report zones |

---

## 3. TLP-Specific Observations

### 3.1 Enforcement Patterns (Community-Reported)
- **Sporadic, not systematic:** GM presence is described as "seldomly enforce the rules" on some TLPs, but ban waves do occur.
- **Report-driven:** Most suspensions/bans appear triggered by player reports rather than proactive GM patrols.
- **Friendly fire:** Ban waves sometimes catch non-botters using legitimate boxing tools (ISBoxer, auto-follow).
- **Tool detection:** Third-party injection tools (MacroQuest, etc.) carry the highest permanent ban risk.

### 3.2 Server Variability
| Server Type | GM Activity | Boxing Tolerance | Notes |
|-------------|-------------|------------------|-------|
| **Newest TLP (Frostreaver-era)** | Medium | Low | Higher scrutiny on launch; relaxes over time |
| **Mid-progression TLP** | Low-Medium | Medium | Established meta; GM attention drifts to newer servers |
| **Live Servers** | Low | High | Boxing widely tolerated; automation risk lowest |

---

## 4. Safe Operating Windows (Provisional)

> **Note:** These are estimates based on community patterns. SME validation required.

| Window | Risk Level | Recommended Action |
|--------|-----------|-------------------|
| **01:00 - 06:00 server time** | Low (Tier 3) | Standard autonomous operation |
| **06:00 - 12:00 server time** | Medium (Tier 2) | Reduced box count, zone rotation |
| **12:00 - 18:00 server time** | Medium-High (Tier 2) | Restricted to monitored sessions |
| **18:00 - 01:00 server time** | High (Tier 1-2) | Human-in-the-loop or pause |
| **Expansion launch +48h** | Critical (Tier 1) | Full pause |
| **Server unlock +24h** | Critical (Tier 1) | Full pause |
| **Seasonal events** | Elevated (Tier 2) | 50% hour reduction |

---

## 5. SME Questions (Pending Response)

The following questions were posed to Matt / Blownt for validation:

1. **Which TLP servers have highest GM enforcement activity in your experience?**
   - *Research suggests newest TLPs (Frostreaver-era) have highest scrutiny; mid-progression servers lower.*
   - *Awaiting SME confirmation.*

2. **Are there known safe hours with lower GM presence?**
   - *Community reports suggest 1am-6am server time as lowest risk.*
   - *Awaiting SME confirmation.*

3. **Have you seen mass ban waves tied to specific expansions or content releases?**
   - *Historical evidence: ban waves occur post-launch, often catching legitimate boxers.*
   - *Awaiting SME timeline confirmation.*

4. **Is there a known difference in risk between boxing in a group vs solo farming?**
   - *Research indicates 6-box groups are higher visibility/report targets than 1-2 box solo farming.*
   - *Awaiting SME operational confirmation.*

---

## 6. Recommendations for M6 Autonomous Operation

1. **Implement tiered pause system** tied to expansion calendar and server unlock schedule.
2. **Enforce 2-box maximum** on TLP servers; reserve 6-box for live only.
3. **Require human-in-the-loop** for tell response during all autonomous sessions.
4. **Log all sessions** with timestamps, zone, box count, and any GM interaction for audit.
5. **Subscribe to community channels** (Reddit, Discord, forums) for real-time ban wave alerts.
6. **Re-evaluate this matrix quarterly** or after any observed ban wave.

---

## 7. Document History

| Date | Author | Change |
|------|--------|--------|
| 2025-05-05 | AutoShip Hermes (#342) | Initial research-based draft from public community sources |
| TBD | Matt / Blownt | SME validation and field corrections |

---

*This document is a living risk assessment. Community input and SME validation are required before M6 sustained autonomous operation is approved on TLP servers.*
