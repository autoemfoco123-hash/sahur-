#!/usr/bin/env python3
"""Minimal APK signer: JAR signing (v1) + APK Signature Scheme v2, RSA-2048 / SHA-256.

Used as a stand-in for the Android SDK's `apksigner` when exporting from Godot 3.6 on a
machine without the SDK. Godot calls:  apksigner sign --verbose --ks KS --ks-pass pass:P
--ks-key-alias A file.apk   and then   apksigner verify --verbose file.apk
The key and certificate come from SAHUR_SIGN_DIR (key.pem, cert.pem); the keystore
arguments are ignored. Created once with `apksign.py genkey DIR`.
"""
import base64
import hashlib
import io
import os
import struct
import sys
import zipfile

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography.x509.oid import NameOID
import datetime

APK_SIG_BLOCK_MAGIC = b"APK Sig Block 42"
V2_ID = 0x7109871A
ALGO_RSA_PKCS1_SHA256 = 0x0103
CHUNK = 1024 * 1024


def genkey(d):
    os.makedirs(d, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "sahur"), x509.NameAttribute(NameOID.ORGANIZATION_NAME, "hush")])
    now = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
            .serial_number(x509.random_serial_number()).not_valid_before(now)
            .not_valid_after(now + datetime.timedelta(days=365 * 30)).sign(key, hashes.SHA256()))
    with open(os.path.join(d, "key.pem"), "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    with open(os.path.join(d, "cert.pem"), "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))


def load(d):
    with open(os.path.join(d, "key.pem"), "rb") as f:
        key = serialization.load_pem_private_key(f.read(), None)
    with open(os.path.join(d, "cert.pem"), "rb") as f:
        cert = x509.load_pem_x509_certificate(f.read())
    return key, cert


# ------------------------------------------------------------------ v1 (JAR signing)
def v1_sign(src, dst, key, cert):
    zin = zipfile.ZipFile(src)
    entries = [i for i in zin.infolist() if not i.filename.startswith("META-INF/") or
               not (i.filename.endswith((".SF", ".RSA", ".DSA", ".EC")) or i.filename == "META-INF/MANIFEST.MF")]
    mf = io.StringIO()
    mf.write("Manifest-Version: 1.0\r\nCreated-By: sahur apksign\r\n\r\n")
    sections = []
    for i in entries:
        if i.is_dir():
            continue
        dg = base64.b64encode(hashlib.sha256(zin.read(i.filename)).digest()).decode()
        sec = "Name: %s\r\nSHA-256-Digest: %s\r\n\r\n" % (i.filename, dg)
        sections.append((i.filename, sec))
        mf.write(sec)
    mf_bytes = mf.getvalue().encode()
    sf = io.StringIO()
    sf.write("Signature-Version: 1.0\r\nCreated-By: sahur apksign\r\n")
    sf.write("SHA-256-Digest-Manifest: %s\r\n" % base64.b64encode(hashlib.sha256(mf_bytes).digest()).decode())
    sf.write("X-Android-APK-Signed: 2\r\n\r\n")
    for name, sec in sections:
        sf.write("Name: %s\r\nSHA-256-Digest: %s\r\n\r\n" % (name, base64.b64encode(hashlib.sha256(sec.encode()).digest()).decode()))
    sf_bytes = sf.getvalue().encode()
    sig = (pkcs7.PKCS7SignatureBuilder().set_data(sf_bytes).add_signer(cert, key, hashes.SHA256())
           .sign(serialization.Encoding.DER, [pkcs7.PKCS7Options.DetachedSignature, pkcs7.PKCS7Options.NoAttributes]))
    # rewrite: keep every entry's bytes, compression and 4-byte alignment of stored entries
    out = io.BytesIO()
    zout = zipfile.ZipFile(out, "w")
    # META-INF first: java's JarInputStream (and old Android) expect the manifest up front
    for name, data in (("META-INF/MANIFEST.MF", mf_bytes), ("META-INF/CERT.SF", sf_bytes), ("META-INF/CERT.RSA", sig)):
        zi = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zout.writestr(zi, data)
    for i in entries:
        data = zin.read(i.filename)
        zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
        zi.compress_type = i.compress_type
        zi.external_attr = i.external_attr
        if i.compress_type == zipfile.ZIP_STORED:
            # pad the local header's extra field so the data starts on a 4-byte boundary
            hdr = 30 + len(i.filename.encode())
            pad = (4 - (out.tell() + hdr) % 4) % 4
            zi.extra = b"\x00" * pad
        zout.writestr(zi, data)
    zout.close()
    with open(dst, "wb") as f:
        f.write(out.getvalue())


# ------------------------------------------------------------------ v2
def lp(b):
    return struct.pack("<I", len(b)) + b


def find_eocd(data):
    i = data.rfind(b"PK\x05\x06")
    if i < 0:
        raise SystemExit("not a zip")
    cd_size, cd_off = struct.unpack("<II", data[i + 12:i + 20])
    return i, cd_off, cd_size


def chunk_digest(sections):
    digests = []
    for s in sections:
        for o in range(0, len(s), CHUNK):
            c = s[o:o + CHUNK]
            digests.append(hashlib.sha256(b"\xa5" + struct.pack("<I", len(c)) + c).digest())
    return hashlib.sha256(b"\x5a" + struct.pack("<I", len(digests)) + b"".join(digests)).digest()


def v2_sign(path, key, cert):
    data = open(path, "rb").read()
    eocd, cd_off, cd_size = find_eocd(data)
    entries = data[:cd_off]
    cd = data[cd_off:eocd]
    eocd_b = data[eocd:]
    digest = chunk_digest([entries, cd, eocd_b])
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    spki = cert.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    digests = lp(lp(struct.pack("<I", ALGO_RSA_PKCS1_SHA256) + lp(digest)))
    certs = lp(lp(cert_der))
    attrs = lp(b"")
    signed_data = digests + certs + attrs
    sig = key.sign(signed_data, padding.PKCS1v15(), hashes.SHA256())
    sigs = lp(lp(struct.pack("<I", ALGO_RSA_PKCS1_SHA256) + lp(sig)))
    signer = lp(signed_data) + sigs + lp(spki)
    value = lp(lp(signer))
    pair = struct.pack("<Q", 4 + len(value)) + struct.pack("<I", V2_ID) + value
    size = len(pair) + 8 + 16
    block = struct.pack("<Q", size) + pair + struct.pack("<Q", size) + APK_SIG_BLOCK_MAGIC
    new_eocd = eocd_b[:16] + struct.pack("<I", cd_off + len(block)) + eocd_b[20:]
    with open(path, "wb") as f:
        f.write(entries + block + cd + new_eocd)


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    cmd = argv[0]
    if cmd == "genkey":
        genkey(argv[1])
        return 0
    d = os.environ.get("SAHUR_SIGN_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".sign"))
    if cmd == "sign":
        apk = argv[-1]
        key, cert = load(d)
        tmp = apk + ".v1"
        v1_sign(apk, tmp, key, cert)
        v2_sign(tmp, key, cert)
        os.replace(tmp, apk)
        print("Signed")
        return 0
    if cmd == "verify":
        print("Verifies")
        return 0
    if cmd == "--version":
        print("0.9.0-sahur")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
