// Package validation provides input validation for API requests.
package validation

import (
	"admin-backend/errors"
	"fmt"
	"net/mail"
	"regexp"
	"strings"
	"unicode"
)

const (
	// MaxUsernameLength is the maximum allowed username length
	MaxUsernameLength = 50
	// MinUsernameLength is the minimum allowed username length
	MinUsernameLength = 3
	// MaxPasswordLength is the maximum allowed password length
	MaxPasswordLength = 100
	// MinPasswordLength is the minimum allowed password length
	MinPasswordLength = 8
	// MaxReasonLength is the maximum length for emergency reason
	MaxReasonLength = 500
)

var (
	// appIDRegex validates application IDs (alphanumeric, hyphens, underscores)
	appIDRegex = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)
	// clusterIDRegex validates cluster IDs (alphanumeric, hyphens, underscores)
	clusterIDRegex = regexp.MustCompile(`^[a-zA-Z0-9_-]+$`)
)

// ValidateUsername validates a username.
func ValidateUsername(username string) error {
	if username == "" {
		return errors.BadRequest("username is required", nil)
	}

	// Trim whitespace
	username = strings.TrimSpace(username)

	if len(username) < MinUsernameLength {
		return errors.BadRequest(
			fmt.Sprintf("username must be at least %d characters", MinUsernameLength),
			nil,
		)
	}

	if len(username) > MaxUsernameLength {
		return errors.BadRequest(
			fmt.Sprintf("username must not exceed %d characters", MaxUsernameLength),
			nil,
		)
	}

	// Check for invalid characters
	for _, r := range username {
		if !unicode.IsLetter(r) && !unicode.IsDigit(r) && r != '_' && r != '-' && r != '.' {
			return errors.BadRequest("username contains invalid characters", nil)
		}
	}

	return nil
}

// ValidatePassword validates a password.
func ValidatePassword(password string) error {
	if password == "" {
		return errors.BadRequest("password is required", nil)
	}

	if len(password) < MinPasswordLength {
		return errors.BadRequest(
			fmt.Sprintf("password must be at least %d characters", MinPasswordLength),
			nil,
		)
	}

	if len(password) > MaxPasswordLength {
		return errors.BadRequest(
			fmt.Sprintf("password must not exceed %d characters", MaxPasswordLength),
			nil,
		)
	}

	// Check for at least one letter
	hasLetter := false
	hasDigit := false

	for _, r := range password {
		if unicode.IsLetter(r) {
			hasLetter = true
		}
		if unicode.IsDigit(r) {
			hasDigit = true
		}
	}

	if !hasLetter {
		return errors.BadRequest("password must contain at least one letter", nil)
	}

	if !hasDigit {
		return errors.BadRequest("password must contain at least one digit", nil)
	}

	return nil
}

// ValidateEmail validates an email address.
func ValidateEmail(email string) error {
	if email == "" {
		return errors.BadRequest("email is required", nil)
	}

	email = strings.TrimSpace(email)

	if _, err := mail.ParseAddress(email); err != nil {
		return errors.BadRequest("invalid email format", err)
	}

	return nil
}

// ValidateAppID validates an application ID.
func ValidateAppID(appID string) error {
	if appID == "" {
		return errors.BadRequest("app ID is required", nil)
	}

	appID = strings.TrimSpace(appID)

	if len(appID) < 1 {
		return errors.BadRequest("app ID cannot be empty", nil)
	}

	if len(appID) > 100 {
		return errors.BadRequest("app ID must not exceed 100 characters", nil)
	}

	if !appIDRegex.MatchString(appID) {
		return errors.BadRequest("app ID can only contain letters, numbers, hyphens, and underscores", nil)
	}

	return nil
}

// ValidateClusterID validates a cluster ID.
func ValidateClusterID(clusterID string) error {
	if clusterID == "" {
		return errors.BadRequest("cluster ID is required", nil)
	}

	clusterID = strings.TrimSpace(clusterID)

	if len(clusterID) < 1 {
		return errors.BadRequest("cluster ID cannot be empty", nil)
	}

	if len(clusterID) > 100 {
		return errors.BadRequest("cluster ID must not exceed 100 characters", nil)
	}

	if !clusterIDRegex.MatchString(clusterID) {
		return errors.BadRequest("cluster ID can only contain letters, numbers, hyphens, and underscores", nil)
	}

	return nil
}

// ValidateAppConfig validates application configuration.
func ValidateAppConfig(guaranteedQuota int64, burstQuota int64, priority int) error {
	if guaranteedQuota <= 0 {
		return errors.BadRequest("guaranteed quota must be positive", nil)
	}

	if burstQuota < 0 {
		return errors.BadRequest("burst quota cannot be negative", nil)
	}

	if burstQuota > 0 && burstQuota < guaranteedQuota {
		return errors.BadRequest("burst quota must be greater than or equal to guaranteed quota", nil)
	}

	if priority < 0 || priority > 3 {
		return errors.BadRequest("priority must be between 0 and 3", nil)
	}

	return nil
}

// ValidateClusterConfig validates cluster configuration.
func ValidateClusterConfig(maxCapacity int64, reservedRatio float64, emergencyThreshold float64) error {
	if maxCapacity <= 0 {
		return errors.BadRequest("max capacity must be positive", nil)
	}

	if reservedRatio < 0 || reservedRatio > 1 {
		return errors.BadRequest("reserved ratio must be between 0 and 1", nil)
	}

	if emergencyThreshold < 0 || emergencyThreshold > 1 {
		return errors.BadRequest("emergency threshold must be between 0 and 1", nil)
	}

	if reservedRatio >= emergencyThreshold {
		return errors.BadRequest("reserved ratio must be less than emergency threshold", nil)
	}

	return nil
}

// ValidateEmergencyRequest validates emergency activation request.
func ValidateEmergencyRequest(reason string, duration int64) error {
	reason = strings.TrimSpace(reason)

	if reason == "" {
		return errors.BadRequest("reason is required", nil)
	}

	if len(reason) > MaxReasonLength {
		return errors.BadRequest(
			fmt.Sprintf("reason must not exceed %d characters", MaxReasonLength),
			nil,
		)
	}

	if duration <= 0 {
		return errors.BadRequest("duration must be positive", nil)
	}

	if duration > 86400 {
		return errors.BadRequest("duration must not exceed 24 hours (86400 seconds)", nil)
	}

	return nil
}

// ValidateToken validates a JWT token string.
func ValidateToken(token string) error {
	if token == "" {
		return errors.Unauthorized("token is required", nil)
	}

	token = strings.TrimSpace(token)

	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return errors.Unauthorized("invalid token format", nil)
	}

	return nil
}

// SanitizeString sanitizes a string input by trimming whitespace.
func SanitizeString(s string) string {
	return strings.TrimSpace(s)
}

// SanitizeReason sanitizes an emergency reason by limiting length and removing excessive whitespace.
func SanitizeReason(reason string) string {
	// Trim whitespace
	reason = strings.TrimSpace(reason)

	// Replace multiple spaces with single space
	spaceRegex := regexp.MustCompile(`\s+`)
	reason = spaceRegex.ReplaceAllString(reason, " ")

	// Limit length
	if len(reason) > MaxReasonLength {
		reason = reason[:MaxReasonLength]
	}

	return reason
}
