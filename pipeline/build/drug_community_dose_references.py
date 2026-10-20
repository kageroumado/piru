"""Validate and retain substance.wiki dose references without deriving calculator inputs.

The published model is the evidence: source wording, nulls, explicit bound kinds,
formulations and provenance stay intact. Validation refuses a model the reader
cannot interpret; it never repairs, converts or projects a dose amount.
"""

from __future__ import annotations

import math

from drug_community_timelines import canonical_json, digest

DOSE_REFERENCE_SCHEMA = "drug-community-dose-bands/1"
STATUSES = frozenset({"available", "unavailable", "withdrawn"})
GROUP_KINDS = frozenset({"published_route", "provisional_human"})
AMOUNT_KINDS = frozenset({"range", "exact", "lower_bound", "upper_bound", "text"})


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _strings(value: object) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def _nullable_text(value: object) -> bool:
    return value is None or isinstance(value, str)


def _eligibility(value: object) -> bool:
    return value is None or isinstance(value, bool)


def _number(value: object) -> bool:
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def _amount(amount: object, units: str) -> None:
    _require(isinstance(amount, dict), "dose amount must be an object")
    _require(amount.get("kind") in AMOUNT_KINDS, "unknown dose amount kind")
    for key in ("lower", "upper"):
        _require(key in amount, f"missing dose amount {key}")
        _require(amount[key] is None or _number(amount[key]), f"invalid dose amount {key}")
    for key in ("lowerInclusive", "upperInclusive"):
        _require(key in amount and _eligibility(amount[key]), f"invalid dose amount {key}")
    _require("units" in amount and _nullable_text(amount["units"]), "invalid dose amount units")
    kind, lower, upper = amount["kind"], amount["lower"], amount["upper"]
    if kind == "text":
        _require(
            all(
                amount[key] is None
                for key in ("lower", "upper", "lowerInclusive", "upperInclusive", "units")
            )
            and amount.get("basis") == "unparsed",
            "text dose amount must not claim numeric bounds or units",
        )
        return
    _require(
        bool(amount["units"] and amount["units"].strip())
        and amount["units"] == units
        and amount.get("basis") in ("source_numeric", "parsed_text"),
        "numeric dose amount needs its group's units and a numeric basis",
    )
    if kind == "lower_bound":
        _require(
            lower is not None and upper is None and amount["upperInclusive"] is None,
            "invalid lower bound",
        )
    elif kind == "upper_bound":
        _require(
            upper is not None and lower is None and amount["lowerInclusive"] is None,
            "invalid upper bound",
        )
    else:
        _require(
            lower is not None and upper is not None and lower <= upper, "invalid dose interval"
        )
        _require(kind != "exact" or lower == upper, "exact dose amount must have equal bounds")


def validate_model(model: object) -> dict:
    """Check the known wire contract, retaining every field of the original object."""
    _require(isinstance(model, dict), "dose reference must be an object")
    _require(model.get("schemaVersion") == DOSE_REFERENCE_SCHEMA, "unknown dose reference schema")
    _require(model.get("status") in STATUSES, "unknown dose reference status")
    _require(isinstance(model.get("groups"), list), "dose reference groups must be an array")
    _require(
        _strings(model.get("notes")) and _strings(model.get("warnings")),
        "invalid dose reference notes or warnings",
    )
    _require(
        isinstance(model.get("reportedAmountDistributions"), list),
        "invalid reported amount distributions",
    )
    group_ids = set()
    for group in model["groups"]:
        _require(isinstance(group, dict), "dose group must be an object")
        _require(
            isinstance(group.get("id"), str) and group["id"] not in group_ids,
            "invalid or duplicate dose group identity",
        )
        group_ids.add(group["id"])
        _require(group.get("kind") in GROUP_KINDS, "unknown dose group kind")
        _require(
            all(isinstance(group.get(key), str) for key in ("sourcePath", "route", "units")),
            "invalid dose group context",
        )
        _require(
            all(
                key in group and _nullable_text(group[key])
                for key in ("formulation", "materialBasis", "populationLimits")
            ),
            "invalid dose group material or population context",
        )
        _require(
            _strings(group.get("notes")) and _strings(group.get("warnings")),
            "invalid dose group notes or warnings",
        )
        _require(
            "calculationEligible" in group and _eligibility(group["calculationEligible"]),
            "invalid dose group calculation eligibility",
        )
        _require(
            isinstance(group.get("sources"), list)
            and isinstance(group.get("observations"), list)
            and isinstance(group.get("bands"), list),
            "invalid dose group evidence or bands",
        )
        _require(
            all(isinstance(observation, dict) for observation in group["observations"]),
            "invalid dose observation",
        )
        observation_ids = {
            observation["id"]
            for observation in group["observations"]
            if isinstance(observation.get("id"), str)
        }
        source_ids = set()
        for source in group["sources"]:
            _require(isinstance(source, dict), "dose source must be an object")
            _require(
                isinstance(source.get("id"), str) and source["id"] not in source_ids,
                "invalid or duplicate dose source identity",
            )
            source_ids.add(source["id"])
            _require(
                isinstance(source.get("title"), str)
                and "url" in source
                and _nullable_text(source["url"])
                and isinstance(source.get("details"), dict),
                "invalid dose source details",
            )
        provisional = group["kind"] == "provisional_human"
        _require(
            not provisional or group["calculationEligible"] is False,
            "provisional dose group must be reference only",
        )
        band_ids = set()
        for band in group["bands"]:
            _require(isinstance(band, dict), "dose band must be an object")
            _require(
                isinstance(band.get("id"), str) and band["id"] not in band_ids,
                "invalid or duplicate dose band identity",
            )
            band_ids.add(band["id"])
            _require(
                all(isinstance(band.get(key), str) for key in ("band", "label", "text", "status")),
                "invalid dose band text or status",
            )
            _require(
                "confidence" in band
                and (
                    band["confidence"] is None
                    or isinstance(band["confidence"], str)
                    or (
                        type(band["confidence"]) in (int, float)
                        and math.isfinite(band["confidence"])
                    )
                ),
                "invalid dose band confidence",
            )
            _require(
                _strings(band.get("sourceIds"))
                and _strings(band.get("sourceObservationIds"))
                and _strings(band.get("notes")),
                "invalid dose band evidence links or notes",
            )
            _require(
                set(band["sourceIds"]) <= source_ids
                and set(band["sourceObservationIds"]) <= observation_ids,
                "unresolved dose evidence reference",
            )
            _require(
                "calculationEligible" in band and _eligibility(band["calculationEligible"]),
                "invalid dose band calculation eligibility",
            )
            _require(
                not (provisional or band["band"] == "fatal")
                or band["calculationEligible"] is False,
                "provisional or fatal dose band must be reference only",
            )
            _require(
                "provenance" in band
                and (band["provenance"] is None or isinstance(band["provenance"], dict)),
                "invalid dose band provenance",
            )
            _amount(band.get("amount"), group["units"])
    if model["status"] == "withdrawn":
        _require(
            not model["groups"] and not model["reportedAmountDistributions"],
            "withdrawn dose reference must not expose groups or distributions",
        )
    else:
        _require(
            (model["status"] == "available") == any(group["bands"] for group in model["groups"]),
            "dose reference availability differs from its bands",
        )
    # This also rejects non-JSON objects and non-finite values anywhere inside
    # otherwise opaque source details, observations, distributions or provenance.
    canonical_json(model)
    return model


def reference_row(record: dict, snapshot_sha256: str) -> dict | None:
    """One snapshot-bound row per source profile; older snapshots need no backfill."""
    dosages = record.get("dosages")
    if not isinstance(dosages, dict) or "dose_bands" not in dosages:
        return None
    try:
        model = validate_model(dosages["dose_bands"])
    except (ValueError, TypeError) as exc:
        raise ValueError(f"{record.get('drug_name')}: invalid dose reference: {exc}") from exc
    return {
        "record_key": digest([snapshot_sha256, record["drug_name"], "/dosages/dose_bands"]),
        "source_name": record["drug_name"],
        "model_json": canonical_json(model),
        "profile_sha256": digest(record),
        "snapshot_sha256": snapshot_sha256,
    }
