{#- Utilise le nom de schema demande tel quel (dwh, dm_preinscription),
    au lieu de le prefixer par le schema du profil (dwh_dm_preinscription). -#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ custom_schema_name | trim if custom_schema_name else target.schema }}
{%- endmacro %}
