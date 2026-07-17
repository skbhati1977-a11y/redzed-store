(() => {
"use strict";

const REDZED = window.REDZED;
const Core = window.RRCuttingMaster;

if (!REDZED || !Core) {
    console.error("REDZED Patch Engine or Cutting Master Core missing.");
    return;
}

const CARD_STATUS = Object.freeze({
    DRAFT: "draft",
    DECISION_LOCKED: "decision_locked",
    LOT_ASSIGNED: "cutting_lot_assigned",
    READY: "ready_for_cutting",
    STARTED: "cutting_started",
    COMPLETED: "cutting_completed",
    ISSUED: "issued_to_production",
    CANCELLED: "cancelled"
});

const STATUS_FLOW = Object.freeze([
    CARD_STATUS.DRAFT,
    CARD_STATUS.DECISION_LOCKED,
    CARD_STATUS.LOT_ASSIGNED,
    CARD_STATUS.READY,
    CARD_STATUS.STARTED,
    CARD_STATUS.COMPLETED,
    CARD_STATUS.ISSUED
]);

const DEFAULT_DECISION_FIELDS = Object.freeze([
    "sizeCombo",
    "sleeve",
    "border",
    "neck",
    "fit",
    "print",
    "packing"
]);

function clean(value) {
    return String(value ?? "").trim();
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function unique(values) {
    return [...new Set(
        (values || [])
            .map(clean)
            .filter(Boolean)
    )];
}

function nowIso() {
    return new Date().toISOString();
}

function makeId(prefix = "CUT") {
    const random = Math.random()
        .toString(36)
        .slice(2, 9)
        .toUpperCase();

    return `${prefix}-${Date.now()}-${random}`;
}

function alphaSuffix(index) {
    let n = Number(index);
    let result = "";

    do {
        result =
            String.fromCharCode(65 + (n % 26)) +
            result;

        n = Math.floor(n / 26) - 1;
    } while (n >= 0);

    return result;
}

function normalizeAttribute(input, fallbackName) {
    const source = input || {};

    const values = unique(
        Array.isArray(source.values)
            ? source.values
            : source.value !== undefined
                ? [source.value]
                : []
    );

    return {
        key: clean(source.key || fallbackName),
        label: clean(source.label || fallbackName),
        mode: clean(
            source.mode ||
            (values.length > 1 ? "multi" : "default")
        ).toLowerCase(),
        values
    };
}

function cartesianProduct(groups) {
    if (!groups.length) {
        return [[]];
    }

    return groups.reduce(
        (rows, group) => {
            return rows.flatMap(row => {
                return group.values.map(value => {
                    return [
                        ...row,
                        {
                            key: group.key,
                            label: group.label,
                            value
                        }
                    ];
                });
            });
        },
        [[]]
    );
}

const CuttingPlugin = {

    name: "cutting",
    version: "1.1.0",

    app: null,

    state: {
        cards: new Map(),
        lotIndex: new Map(),
        correctionRequests: new Map()
    },

    decision: {},
    cards: {},
    lots: {},
    status: {},
    validation: {},
    correction: {},
    events: {},
    api: {},

    init(app) {
        this.app = app || null;
        this.installEngines();

        console.info(
            "REDZED Cutting Plugin Ready",
            this.version
        );
    },

    installEngines() {
        const plugin = this;

        // --------------------------------------------------
        // VALIDATION ENGINE
        // --------------------------------------------------

        this.validation.require = function requireValue(
            value,
            label
        ) {
            if (!clean(value)) {
                throw new Error(
                    `${label} is required.`
                );
            }
        };

        // --------------------------------------------------
        // EVENT ENGINE
        // --------------------------------------------------

        this.events.emit = function emit(
            eventName,
            detail
        ) {
            window.dispatchEvent(
                new CustomEvent(eventName, {
                    detail: clone(detail)
                })
            );
        };

        // --------------------------------------------------
        // DECISION ENGINE
        // --------------------------------------------------

        this.decision.preview = function previewDecision(
            input = {}
        ) {
            const attributes = [];
            const supplied = input.attributes || {};

            DEFAULT_DECISION_FIELDS.forEach(field => {
                const normalized =
                    normalizeAttribute(
                        supplied[field],
                        field
                    );

                if (normalized.values.length) {
                    attributes.push(normalized);
                }
            });

            (input.customAttributes || [])
                .forEach((attribute, index) => {
                    const normalized =
                        normalizeAttribute(
                            attribute,
                            `custom_${index + 1}`
                        );

                    if (normalized.values.length) {
                        attributes.push(normalized);
                    }
                });

            const invalidModes =
                attributes.filter(attribute => {
                    return ![
                        "default",
                        "single",
                        "multi"
                    ].includes(attribute.mode);
                });

            if (invalidModes.length) {
                throw new Error(
                    `Invalid decision mode: ${
                        invalidModes
                            .map(item => item.label)
                            .join(", ")
                    }`
                );
            }

            const invalidMulti =
                attributes.filter(attribute => {
                    return (
                        attribute.mode === "multi" &&
                        attribute.values.length < 2
                    );
                });

            if (invalidMulti.length) {
                throw new Error(
                    `Multi selection needs at least 2 values: ${
                        invalidMulti
                            .map(item => item.label)
                            .join(", ")
                    }`
                );
            }

            const combinations =
                cartesianProduct(attributes);

            return {
                attributes: clone(attributes),

                totalCombinations:
                    combinations.length,

                combinations:
                    combinations.map(
                        (combination, index) => {
                            return {
                                index: index + 1,

                                decisions:
                                    Object.fromEntries(
                                        combination.map(item => [
                                            item.key,
                                            item.value
                                        ])
                                    ),

                                labels:
                                    Object.fromEntries(
                                        combination.map(item => [
                                            item.key,
                                            item.label
                                        ])
                                    )
                            };
                        }
                    )
            };
        };

        // --------------------------------------------------
        // CARD HELPERS
        // --------------------------------------------------

        this.cards.mustGetMutable =
            function mustGetMutable(cardId) {
                const id = clean(cardId);

                const card =
                    plugin.state.cards.get(id);

                if (!card) {
                    throw new Error(
                        `Cutting Card not found: ${id}`
                    );
                }

                if (
                    card.status ===
                    CARD_STATUS.CANCELLED
                ) {
                    throw new Error(
                        "Cancelled Cutting Card cannot be changed."
                    );
                }

                return card;
            };

        this.cards.touch =
            function touch(
                card,
                type,
                data = {}
            ) {
                const timestamp = nowIso();

                card.updatedAt = timestamp;

                card.history.push({
                    type,
                    at: timestamp,
                    data: clone(data)
                });
            };

        // --------------------------------------------------
        // SINGLE CARD ENGINE
        // --------------------------------------------------

        this.cards.create =
            function createCard(input = {}) {
                const cbNo =
                    clean(input.cbNo);

                const childNo =
                    clean(input.childNo);

                const devNo =
                    clean(input.devNo);

                plugin.validation.require(
                    cbNo,
                    "CB No."
                );

                plugin.validation.require(
                    childNo,
                    "Child No."
                );

                const duplicate =
                    [...plugin.state.cards.values()]
                        .find(card => {
                            return (
                                card.cbNo === cbNo &&
                                card.childNo === childNo &&
                                clean(card.devNo) === devNo &&
                                card.status !==
                                CARD_STATUS.CANCELLED
                            );
                        });

                if (duplicate) {
                    throw new Error(
                        `Card already exists for ${cbNo} / ${childNo}${
                            devNo
                                ? ` / ${devNo}`
                                : ""
                        }.`
                    );
                }

                const timestamp = nowIso();

                const card = {
                    id: makeId("CARD"),

                    cbNo,
                    childNo,

                    devNo:
                        devNo || null,

                    decisionInputs:
                        clone(
                            input.decisionInputs || {}
                        ),

                    decisionLabels:
                        clone(
                            input.decisionLabels || {}
                        ),

                    cuttingLotNo: null,

                    cutQty: null,

                    status:
                        CARD_STATUS.DRAFT,

                    productionIssuedAt:
                        null,

                    createdAt:
                        timestamp,

                    updatedAt:
                        timestamp,

                    history: [
                        {
                            type:
                                "card_created",

                            at:
                                timestamp,

                            data: {
                                cbNo,
                                childNo,
                                devNo:
                                    devNo || null
                            }
                        }
                    ]
                };

                plugin.state.cards.set(
                    card.id,
                    card
                );

                plugin.events.emit(
                    "cutting:card-created",
                    clone(card)
                );

                return clone(card);
            };

        // --------------------------------------------------
        // CHILD / DEV CARD BUILDER
        // --------------------------------------------------

        this.cards.build =
            function buildCards(input = {}) {
                const cbNo =
                    clean(input.cbNo);

                const childNo =
                    clean(input.childNo);

                plugin.validation.require(
                    cbNo,
                    "CB No."
                );

                plugin.validation.require(
                    childNo,
                    "Child No."
                );

                const preview =
                    plugin.decision.preview(
                        input.decision || {}
                    );

                const needsDevelopment =
                    preview.totalCombinations > 1;

                return preview.combinations.map(
                    (combination, index) => {
                        const devNo =
                            needsDevelopment
                                ? `${childNo}${alphaSuffix(index)}`
                                : "";

                        return plugin.cards.create({
                            cbNo,
                            childNo,
                            devNo,

                            decisionInputs:
                                combination.decisions,

                            decisionLabels:
                                combination.labels
                        });
                    }
                );
            };

        this.cards.get =
            function getCard(cardId) {
                const card =
                    plugin.state.cards.get(
                        clean(cardId)
                    );

                return card
                    ? clone(card)
                    : null;
            };

        this.cards.list =
            function listCards(filters = {}) {
                return [
                    ...plugin.state.cards.values()
                ]
                    .filter(card => {
                        if (
                            filters.cbNo &&
                            card.cbNo !==
                            clean(filters.cbNo)
                        ) {
                            return false;
                        }

                        if (
                            filters.childNo &&
                            card.childNo !==
                            clean(filters.childNo)
                        ) {
                            return false;
                        }

                        if (
                            filters.devNo !== undefined &&
                            clean(card.devNo) !==
                            clean(filters.devNo)
                        ) {
                            return false;
                        }

                        if (
                            filters.status &&
                            card.status !==
                            filters.status
                        ) {
                            return false;
                        }

                        return true;
                    })
                    .map(clone);
            };

        // --------------------------------------------------
        // DECISION INPUT EDIT / LOCK
        // --------------------------------------------------

        this.cards.setDecisionInputs =
            function setDecisionInputs(
                cardId,
                decisionInputs
            ) {
                const card =
                    plugin.cards
                        .mustGetMutable(cardId);

                if (
                    card.status !==
                    CARD_STATUS.DRAFT
                ) {
                    throw new Error(
                        "Decision Inputs can only be edited while the card is Draft."
                    );
                }

                card.decisionInputs =
                    clone(
                        decisionInputs || {}
                    );

                plugin.cards.touch(
                    card,
                    "decision_inputs_updated",
                    {
                        decisionInputs:
                            card.decisionInputs
                    }
                );

                return clone(card);
            };

        this.cards.lockDecision =
            function lockDecision(cardId) {
                return plugin.status.move(
                    cardId,
                    CARD_STATUS.DECISION_LOCKED
                );
            };

        // --------------------------------------------------
        // LOT ENGINE
        // Sequence:
        // Decision Inputs
        // Cutting Lot No.
        // Cut Qty
        // --------------------------------------------------

        this.lots.assign =
            function assignLot(
                cardId,
                cuttingLotNo,
                actor = {}
            ) {
                const card =
                    plugin.cards
                        .mustGetMutable(cardId);

                const lotNo =
                    clean(cuttingLotNo);

                plugin.validation.require(
                    lotNo,
                    "Cutting Lot No."
                );

                if (
                    card.status !==
                    CARD_STATUS.DECISION_LOCKED
                ) {
                    throw new Error(
                        "Cutting Lot No. can only be assigned after Decision Inputs are locked."
                    );
                }

                const lotKey =
                    lotNo.toUpperCase();

                const existingCardId =
                    plugin.state.lotIndex.get(
                        lotKey
                    );

                if (
                    existingCardId &&
                    existingCardId !== card.id
                ) {
                    throw new Error(
                        `Cutting Lot No. ${lotNo} already exists.`
                    );
                }

                card.cuttingLotNo =
                    lotNo;

                plugin.state.lotIndex.set(
                    lotKey,
                    card.id
                );

                plugin.cards.touch(
                    card,
                    "cutting_lot_assigned",
                    {
                        cuttingLotNo:
                            lotNo,

                        assignedBy:
                            clean(
                                actor.name ||
                                actor.id ||
                                "system"
                            )
                    }
                );

                plugin.status.setDirect(
                    card,
                    CARD_STATUS.LOT_ASSIGNED
                );

                plugin.events.emit(
                    "cutting:lot-assigned",
                    clone(card)
                );

                return clone(card);
            };

        this.lots.setCutQty =
            function setCutQty(
                cardId,
                qty,
                actor = {}
            ) {
                const card =
                    plugin.cards
                        .mustGetMutable(cardId);

                const numericQty =
                    Number(qty);

                if (!card.cuttingLotNo) {
                    throw new Error(
                        "Cutting Lot No. must be assigned before Cut Qty."
                    );
                }

                if (
                    !Number.isInteger(numericQty) ||
                    numericQty <= 0
                ) {
                    throw new 
                        Error(
                        "Cut Qty must be a positive whole number."
                    );
                }

                if (
                    ![
                        CARD_STATUS.LOT_ASSIGNED,
                        CARD_STATUS.READY
                    ].includes(card.status)
                ) {
                    throw new Error(
                        "Cut Qty cannot be changed at the current card status."
                    );
                }

                card.cutQty =
                    numericQty;

                plugin.cards.touch(
                    card,
                    "cut_qty_updated",
                    {
                        cutQty:
                            numericQty,

                        updatedBy:
                            clean(
                                actor.name ||
                                actor.id ||
                                "system"
                            )
                    }
                );

                return clone(card);
            };

        this.lots.find =
            function findByLotNo(
                cuttingLotNo
            ) {
                const lotKey =
                    clean(cuttingLotNo)
                        .toUpperCase();

                const cardId =
                    plugin.state.lotIndex.get(
                        lotKey
                    );

                return cardId
                    ? plugin.cards.get(cardId)
                    : null;
            };

        // --------------------------------------------------
        // STATUS ENGINE
        // No QC
        // --------------------------------------------------

        this.status.setDirect =
            function setDirect(
                card,
                status
            ) {
                card.status =
                    status;

                card.updatedAt =
                    nowIso();
            };

        this.status.move =
            function moveStatus(
                cardId,
                nextStatus,
                actor = {}
            ) {
                const card =
                    plugin.cards
                        .mustGetMutable(cardId);

                const target =
                    clean(nextStatus);

                if (
                    !STATUS_FLOW.includes(target)
                ) {
                    throw new Error(
                        `Invalid Cutting Card status: ${target}`
                    );
                }

                const currentIndex =
                    STATUS_FLOW.indexOf(
                        card.status
                    );

                const targetIndex =
                    STATUS_FLOW.indexOf(
                        target
                    );

                if (
                    targetIndex !==
                    currentIndex + 1
                ) {
                    throw new Error(
                        `Invalid status move: ${card.status} -> ${target}.`
                    );
                }

                if (
                    target ===
                    CARD_STATUS.LOT_ASSIGNED &&
                    !card.cuttingLotNo
                ) {
                    throw new Error(
                        "Assign Cutting Lot No. before moving to Lot Assigned."
                    );
                }

                if (
                    target ===
                    CARD_STATUS.READY &&
                    !card.cutQty
                ) {
                    throw new Error(
                        "Fill Cut Qty before marking Ready for Cutting."
                    );
                }

                const oldStatus =
                    card.status;

                if (
                    target ===
                    CARD_STATUS.ISSUED
                ) {
                    card.productionIssuedAt =
                        nowIso();
                }

                plugin.status.setDirect(
                    card,
                    target
                );

                plugin.cards.touch(
                    card,
                    "status_changed",
                    {
                        from:
                            oldStatus,

                        to:
                            target,

                        changedBy:
                            clean(
                                actor.name ||
                                actor.id ||
                                "system"
                            )
                    }
                );

                plugin.events.emit(
                    "cutting:status-changed",
                    clone(card)
                );

                return clone(card);
            };

        // --------------------------------------------------
        // CORRECTION ENGINE
        // --------------------------------------------------

        this.correction.mustGetMutable =
            function mustGetCorrection(
                requestId
            ) {
                const request =
                    plugin.state
                        .correctionRequests
                        .get(
                            clean(requestId)
                        );

                if (!request) {
                    throw new Error(
                        `Correction Request not found: ${requestId}`
                    );
                }

                return request;
            };

        this.correction.request =
            function requestCorrection(
                input = {}
            ) {
                const card =
                    plugin.cards
                        .mustGetMutable(
                            input.cardId
                        );

                const newLotNo =
                    clean(
                        input.newCuttingLotNo
                    );

                const reason =
                    clean(input.reason);

                const requestedBy =
                    clean(input.requestedBy);

                plugin.validation.require(
                    newLotNo,
                    "New Cutting Lot No."
                );

                plugin.validation.require(
                    reason,
                    "Correction reason"
                );

                plugin.validation.require(
                    requestedBy,
                    "Requested By"
                );

                if (!card.cuttingLotNo) {
                    throw new Error(
                        "This card has no Cutting Lot No. to correct."
                    );
                }

                if (
                    card.status ===
                    CARD_STATUS.ISSUED ||
                    card.productionIssuedAt
                ) {
                    throw new Error(
                        "Lot is already issued to Production. Use Cancel & Reissue."
                    );
                }

                const duplicateId =
                    plugin.state.lotIndex.get(
                        newLotNo.toUpperCase()
                    );

                if (
                    duplicateId &&
                    duplicateId !== card.id
                ) {
                    throw new Error(
                        `Cutting Lot No. ${newLotNo} already exists.`
                    );
                }

                const request = {
                    id:
                        makeId("CORR"),

                    cardId:
                        card.id,

                    oldCuttingLotNo:
                        card.cuttingLotNo,

                    newCuttingLotNo:
                        newLotNo,

                    reason,
                    requestedBy,

                    status:
                        "pending",

                    requestedAt:
                        nowIso(),

                    approvedBy:
                        null,

                    approvedAt:
                        null,

                    rejectedBy:
                        null,

                    rejectedAt:
                        null
                };

                plugin.state
                    .correctionRequests
                    .set(
                        request.id,
                        request
                    );

                plugin.events.emit(
                    "cutting:correction-requested",
                    clone(request)
                );

                return clone(request);
            };

        this.correction.approve =
            function approveCorrection(
                requestId,
                approvedBy
            ) {
                const request =
                    plugin.correction
                        .mustGetMutable(
                            requestId
                        );

                const approver =
                    clean(approvedBy);

                plugin.validation.require(
                    approver,
                    "Approved By"
                );

                if (
                    request.status !==
                    "pending"
                ) {
                    throw new Error(
                        "Correction Request is already closed."
                    );
                }

                const card =
                    plugin.cards
                        .mustGetMutable(
                            request.cardId
                        );

                if (
                    card.status ===
                    CARD_STATUS.ISSUED ||
                    card.productionIssuedAt
                ) {
                    throw new Error(
                        "Lot was issued to Production after the request. Use Cancel & Reissue."
                    );
                }

                const newKey =
                    request
                        .newCuttingLotNo
                        .toUpperCase();

                const duplicateId =
                    plugin.state.lotIndex.get(
                        newKey
                    );

                if (
                    duplicateId &&
                    duplicateId !== card.id
                ) {
                    throw new Error(
                        `Cutting Lot No. ${request.newCuttingLotNo} already exists.`
                    );
                }

                plugin.state.lotIndex.delete(
                    request
                        .oldCuttingLotNo
                        .toUpperCase()
                );

                plugin.state.lotIndex.set(
                    newKey,
                    card.id
                );

                card.cuttingLotNo =
                    request.newCuttingLotNo;

                plugin.cards.touch(
                    card,
                    "cutting_lot_corrected",
                    {
                        oldCuttingLotNo:
                            request.oldCuttingLotNo,

                        newCuttingLotNo:
                            request.newCuttingLotNo,

                        reason:
                            request.reason,

                        requestedBy:
                            request.requestedBy,

                        approvedBy:
                            approver
                    }
                );

                request.status =
                    "approved";

                request.approvedBy =
                    approver;

                request.approvedAt =
                    nowIso();

                plugin.events.emit(
                    "cutting:correction-approved",
                    {
                        request:
                            clone(request),

                        card:
                            clone(card)
                    }
                );

                return {
                    request:
                        clone(request),

                    card:
                        clone(card)
                };
            };

        this.correction.reject =
            function rejectCorrection(
                requestId,
                rejectedBy,
                note = ""
            ) {
                const request =
                    plugin.correction
                        .mustGetMutable(
                            requestId
                        );

                const rejector =
                    clean(rejectedBy);

                plugin.validation.require(
                    rejector,
                    "Rejected By"
                );

                if (
                    request.status !==
                    "pending"
                ) {
                    throw new Error(
                        "Correction Request is already closed."
                    );
                }

                request.status =
                    "rejected";

                request.rejectedBy =
                    rejector;

                request.rejectedAt =
                    nowIso();

                request.rejectionNote =
                    clean(note);

                plugin.events.emit(
                    "cutting:correction-rejected",
                    clone(request)
                );

                return clone(request);
            };

        // --------------------------------------------------
        // CANCEL & REISSUE
        // For Production-issued lots
        // --------------------------------------------------

        this.correction.cancelAndReissue =
            function cancelAndReissue(
                input = {}
            ) {
                const oldCard =
                    plugin.cards
                        .mustGetMutable(
                            input.cardId
                        );

                const newLotNo =
                    clean(
                        input.newCuttingLotNo
                    );

                const reason =
                    clean(input.reason);

                const approvedBy =
                    clean(input.approvedBy);

                plugin.validation.require(
                    newLotNo,
                    "New Cutting Lot No."
                );

                plugin.validation.require(
                    reason,
                    "Cancel & Reissue reason"
                );

                plugin.validation.require(
                    approvedBy,
                    "Approved By"
                );

                if (
                    !oldCard.productionIssuedAt &&
                    oldCard.status !==
                    CARD_STATUS.ISSUED
                ) {
                    throw new Error(
                        "Cancel & Reissue is for lots already issued to Production."
                    );
                }

                const newKey =
                    newLotNo.toUpperCase();

                if (
                    plugin.state
                        .lotIndex
                        .has(newKey)
                ) {
                    throw new Error(
                        `Cutting Lot No. ${newLotNo} already exists.`
                    );
                }

                const oldStatus =
                    oldCard.status;

                oldCard.status =
                    CARD_STATUS.CANCELLED;

                plugin.cards.touch(
                    oldCard,
                    "card_cancelled_for_reissue",
                    {
                        reason,
                        approvedBy,
                        previousStatus:
                            oldStatus
                    }
                );

                const timestamp =
                    nowIso();

                const newCard = {
                    ...clone(oldCard),

                    id:
                        makeId("CARD"),

                    cuttingLotNo:
                        newLotNo,

                    status:
                        CARD_STATUS.LOT_ASSIGNED,

                    productionIssuedAt:
                        null,

                    createdAt:
                        timestamp,

                    updatedAt:
                        timestamp,

                    history: [
                        {
                            type:
                                "reissued_from_cancelled_card",

                            at:
                                timestamp,

                            data: {
                                oldCardId:
                                    oldCard.id,

                                oldCuttingLotNo:
                                    oldCard.cuttingLotNo,

                                reason,
                                approvedBy
                            }
                        }
                    ]
                };

                plugin.state.cards.set(
                    newCard.id,
                    newCard
                );

                plugin.state.lotIndex.set(
                    newKey,
                    newCard.id
                );

                plugin.events.emit(
                    "cutting:lot-reissued",
                    {
                        cancelledCard:
                            clone(oldCard),

                        newCard:
                            clone(newCard)
                    }
                );

                return {
                    cancelledCard:
                        clone(oldCard),

                    newCard:
                        clone(newCard)
                };
            };

        // --------------------------------------------------
        // PUBLIC API
        // --------------------------------------------------

        this.api = {
            CARD_STATUS,
            STATUS_FLOW,

            previewDecision(input) {
                return plugin
                    .decision
                    .preview(input);
            },

            buildCards(input) {
                return plugin
                    .cards
                    .build(input);
            },

            createCard(input) {
                return plugin
                    .cards
                    .create(input);
            },

            getCard(cardId) {
                return plugin
                    .cards
                    .get(cardId);
            },

            listCards(filters) {
                return plugin
                    .cards
                    .list(filters);
            },

            setDecisionInputs(
                cardId,
                inputs
            ) {
                return plugin
                    .cards
                    .setDecisionInputs(
                        cardId,
                        inputs
                    );
            },

            lockDecision(cardId) {
                return plugin
                    .cards
                    .lockDecision(cardId);
            },

            assignCuttingLot(
                cardId,
                lotNo,
                actor
            ) {
                return plugin
                    .lots
                    .assign(
                        cardId,
                        lotNo,
                        actor
                    );
            },

            setCutQty(
                cardId,
                qty,
                actor
            ) {
                return plugin
                    .lots
                    .setCutQty(
                        cardId,
                        qty,
                        actor
                    );
            },

            findByCuttingLot(lotNo) {
                return plugin
                    .lots
                    .find(lotNo);
            },

            moveStatus(
                cardId,
                status,
                actor
            ) {
                return plugin
                      .status
                    .move(
                        cardId,
                        status,
                        actor
                    );
            },

            requestLotCorrection(input) {
                return plugin
                    .correction
                    .request(input);
            },

            approveLotCorrection(
                requestId,
                approvedBy
            ) {
                return plugin
                    .correction
                    .approve(
                        requestId,
                        approvedBy
                    );
            },

            rejectLotCorrection(
                requestId,
                rejectedBy,
                note
            ) {
                return plugin
                    .correction
                    .reject(
                        requestId,
                        rejectedBy,
                        note
                    );
            },

            cancelAndReissueLot(input) {
                return plugin
                    .correction
                    .cancelAndReissue(input);
            }
        };
    }
};

REDZED.use(
    "cutting",
    CuttingPlugin
);

})();
  
