#!/bin/bash

# ============================================================
#  Project:   commons-certificate.sh
#  Author:    Fabrice TRAN-XUAN
#  Created:   2025-08-10
#
#  License:   MIT License
#
#  Permission is hereby granted, free of charge, to any person
#  obtaining a copy of this software and associated documentation
#  files (the "Software"), to deal in the Software without
#  restriction, including without limitation the rights to use,
#  copy, modify, merge, publish, distribute, sublicense, and/or
#  sell copies of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following
#  conditions:
#
#  The above copyright notice and this permission notice shall be
#  included in all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#  OTHER DEALINGS IN THE SOFTWARE.
# ============================================================

#
# show_cert_summary
# This function displays a summary of a given X.509 certificate file.
# Arguments:
#   - CERT_FILE_ARG: The certificate file to analyze (PEM format)
#
show_cert_summary() {
  local CERT_FILE_ARG="$1"
  
  if [ -z "$CERT_FILE_ARG" ] || [ ! -f "$CERT_FILE_ARG" ]; then
    printf 'Error: cert file missing or not found: %s\n' "$CERT_FILE_ARG" >&2
    return 2
  fi

  local SUBJ_ARG ISSUER_ARG NOTBEFORE_ARG NOTAFTER_ARG SERIAL_ARG SIGALG_ARG PUBALG_ARG PUBSIZE_ARG \
        BC_ARG KU_ARG EKU_ARG SAN_ARG SHA1_ARG SHA256_ARG NOW_ARG VERDICT_ARG

  SUBJ_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -subject 2>/dev/null | sed 's/subject= //')
  ISSUER_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -issuer 2>/dev/null | sed 's/issuer= //')
  NOTBEFORE_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -startdate 2>/dev/null | sed 's/notBefore=//')
  NOTAFTER_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
  SERIAL_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -serial 2>/dev/null | sed 's/serial=//')
  SIGALG_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -text 2>/dev/null | awk -F': ' '/Signature Algorithm/ {print $2; exit}')
  PUBALG_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -text 2>/dev/null | awk '/Public Key Algorithm/ {print $NF; exit}')
  PUBSIZE_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -text 2>/dev/null | awk '/Public-Key/ {gsub(/[^0-9]/,"",$0); print $2; exit}')
  BC_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -text 2>/dev/null | awk '/X509v3 Basic Constraints/ {getline; print; exit}')
  KU_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -text 2>/dev/null | awk '/X509v3 Key Usage/{getline; print; exit}')
  EKU_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -text 2>/dev/null | awk '/X509v3 Extended Key Usage/{getline; print; exit}')
  SAN_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -text 2>/dev/null | sed -n '/Subject Alternative Name/,$p' | sed -n '1,4p' | tr -d '\n' | sed 's/Subject Alternative Name: //; s/ //g')
  SHA1_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -fingerprint -sha1 2>/dev/null | sed 's/SHA1 Fingerprint=//')
  SHA256_ARG=$(openssl x509 -in "$CERT_FILE_ARG" -noout -fingerprint -sha256 2>/dev/null | sed 's/SHA256 Fingerprint=//')

  NOW_ARG=$(date -u +"%s")
  to_epoch_arg(){ date -u -d "$1" +"%s" 2>/dev/null || date -u -j -f "%b %e %T %Y GMT" "$1" +"%s" 2>/dev/null || echo 0; }

  local NB_EPOCH_ARG NA_EPOCH_ARG
  NB_EPOCH_ARG=$(to_epoch_arg "$NOTBEFORE_ARG")
  NA_EPOCH_ARG=$(to_epoch_arg "$NOTAFTER_ARG")

  if [ "$NB_EPOCH_ARG" -eq 0 ] || [ "$NA_EPOCH_ARG" -eq 0 ]; then
    VERDICT_ARG="could not parse validity"
  elif [ "$NOW_ARG" -lt "$NB_EPOCH_ARG" ]; then
    VERDICT_ARG="not yet valid"
  elif [ "$NOW_ARG" -gt "$NA_EPOCH_ARG" ]; then
    VERDICT_ARG="expired"
  else
    VERDICT_ARG="valid"
  fi

  cat <<EOF
Subject:           ${SUBJ_ARG:-N/A}
Issuer:            ${ISSUER_ARG:-N/A}
Validity:          ${NOTBEFORE_ARG:-N/A}  ->  ${NOTAFTER_ARG:-N/A}  (${VERDICT_ARG})
Serial:            ${SERIAL_ARG:-N/A}
Signature Alg:     ${SIGALG_ARG:-N/A}
Public Key:        ${PUBALG_ARG:-N/A} ${PUBSIZE_ARG:+(${PUBSIZE_ARG} bits)}
Basic Constraints: ${BC_ARG:-N/A}
Key Usage:         ${KU_ARG:-N/A}
Ext Key Usage:     ${EKU_ARG:-N/A}
SANs:              ${SAN_ARG:-N/A}
Fingerprint SHA1:  ${SHA1_ARG:-N/A}
Fingerprint SHA256:${SHA256_ARG:-N/A}
EOF
}
