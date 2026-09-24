#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <sstream>
#include <optional>

namespace Slic3r {
    struct SignerSummary {
        // generic
        std::array<uint8_t, 32> cert_sha256;
        std::array<uint8_t, 32> spki_sha256;
        std::string subject_dn;
        std::string issuer_dn;

        // macOS only
        std::string team_id;

        SignerSummary() {
            cert_sha256.fill(0);
            spki_sha256.fill(0);
        }

        std::string as_print() const {
            std::stringstream ss;
            ss << " subject_dn: " << subject_dn << " issuer_dn: " << issuer_dn << " team_id: " << team_id;
            return ss.str();
        }
    };

    bool IsSamePublisher(const SignerSummary& a, const SignerSummary& b);

    std::optional<SignerSummary> SummarizeSelf();

    std::optional<SignerSummary> SummarizeModule(const std::string& path_utf8);

    // True if the module at path_utf8 has a valid code signature chaining to Apple
    // whose leaf certificate was issued to the given Apple team ID. macOS only;
    // always false elsewhere.
    bool IsSignedByTeam(const std::string& path_utf8, const std::string& team_id);
}