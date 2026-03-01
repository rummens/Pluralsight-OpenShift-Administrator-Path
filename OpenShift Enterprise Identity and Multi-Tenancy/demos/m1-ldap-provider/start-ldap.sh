docker run --rm --name demo-ldap \
  -p 389:389 -p 636:636 \
  -e LDAP_ORGANISATION="Demo" \
  -e LDAP_DOMAIN="example.org" \
  -e LDAP_ADMIN_PASSWORD="adminpw" \
  -v "$PWD/bootstrap.ldif:/container/service/slapd/assets/config/bootstrap/ldif/custom/50-bootstrap.ldif:ro" \
  osixia/openldap:1.5.0 \
  --copy-service
