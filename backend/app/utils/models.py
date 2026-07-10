"""
app/utils/models.py - Pydantic request/response schemas for all API endpoints.
"""
from __future__ import annotations
from datetime import datetime
from typing import Literal, Optional
from pydantic import BaseModel, Field, EmailStr, field_validator

RiskLevel = Literal["low", "moderate", "high"]

# ── Auth / Profile ────────────────────────────────────────────────────────────

class UserPreferencesRequest(BaseModel):
    recovery_type:           str           = "both"
    challenges:              list[str]     = Field(default_factory=list)
    goals:                   list[str]     = Field(default_factory=list)
    custom_challenge:        Optional[str] = None
    emergency_contact_email: Optional[EmailStr] = None
    timezone:                str           = "UTC"

class ConsentRequest(BaseModel):
    email_reminders:      bool = False
    therapist_escalation: bool = False
    rehab_escalation:     bool = False
    data_analytics:       bool = False

class ConsentResponse(BaseModel):
    user_id:              str
    email_reminders:      bool
    therapist_escalation: bool
    rehab_escalation:     bool
    data_analytics:       bool
    updated_at:           datetime

# ── Journal ───────────────────────────────────────────────────────────────────

class JournalEntryRequest(BaseModel):
    text:       str          = Field(..., min_length=10, max_length=10_000)
    mood_score: Optional[int]= Field(None, ge=1, le=10)

    @field_validator("text")
    @classmethod
    def strip_whitespace(cls, v: str) -> str:
        return v.strip()

class JournalEntryResponse(BaseModel):
    entry_id:                str
    detected_emotion:        str
    pattern_insight:         str
    relapse_risk_level:      RiskLevel
    recommendations:         list[str]
    alternative_suggestions: list[str]
    encouragement_message:   str
    medication_support:      Optional[str] = None
    stigma_reassurance:      Optional[str] = None
    streak:                  int
    escalation_triggered:    bool

# ── Insights ──────────────────────────────────────────────────────────────────

class InsightItem(BaseModel):
    id:                      str
    journal_entry_id:        Optional[str]  = None
    detected_emotion:        str
    pattern_insight:         str
    relapse_risk_level:      RiskLevel
    recommendations:         list[str]
    alternative_suggestions: list[str]      = []
    encouragement:           str
    created_at:              datetime

class InsightsResponse(BaseModel):
    insights: list[InsightItem]
    total:    int

# ── Progress ──────────────────────────────────────────────────────────────────

class WeeklySummary(BaseModel):
    entries_this_week: int
    average_mood:      Optional[float] = None

class BadgeItem(BaseModel):
    badge:      str
    label:      str
    awarded_at: datetime

class StatsResponse(BaseModel):
    current_streak:      int
    longest_streak:      int
    total_entries:       int
    sobriety_start_date: Optional[str]  = None
    last_entry_date:     Optional[str]  = None
    weekly_summary:      WeeklySummary
    latest_risk_level:   str
    latest_emotion:      Optional[str]  = None
    badges:              list[BadgeItem]

# ── Daily Message ─────────────────────────────────────────────────────────────

class DailyMessageResponse(BaseModel):
    message:    str
    streak:     int
    mood_trend: str
    # generated_at removed — frontend does not need it and it caused TZ issues

# ── Generic ───────────────────────────────────────────────────────────────────

class MessageResponse(BaseModel):
    message: str

class ErrorResponse(BaseModel):
    error:  str
    detail: Optional[str] = None
