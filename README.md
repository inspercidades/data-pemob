# PEMOB

Pipeline em R para processamento, harmonização e publicação dos dados da PEMOB
(Pesquisa Nacional de Mobilidade Urbana).

## Estrutura

- `R/` — scripts de processamento
  - `pemob.R`, `pemob_final.R` — pipeline principal (municipal)
  - `pemob_metropolitana.R` — pipeline regiões metropolitanas
  - `pemob_portal.R` — preparação dos arquivos
    JSON consumidos pelo portal
  - `pemob_errors.R` — utilitários de validação
- `data-raw/` — dados brutos PEMOB (2019–2025, municipal e metropolitana)
- `data/` — dicionários, categorias e arquivos derivados
- `tabelas/` — tabelas de referência (códigos, harmonização)

## Saídas do portal

`data/portal/v1/pemob_<ano>.json` (2019–2024) são os artefatos consumidos
pelo frontend do Portal das Cidades.

## Dados harmonizados até 2025

Execute `Rscript tests/test-pemob.R` para conferir os contratos e as
harmonizações e `Rscript R/pemob_2025.R` para gerar os CSVs municipal e
metropolitano em `data/`. As séries anteriores a 2025 vêm da planilha
harmonizada de 2024.
O [roteiro de 2025](ROADMAP-2025.md) registra problemas de cobertura histórica
que precisam ser resolvidos antes de publicar novos arquivos do portal.

## Notas

- Arquivos grandes (`.xlsx`, CSVs harmonizados completos) ficam fora do
  controle de versão — ver `.gitignore`.
- Projeto RStudio: abrir `simu_pemob.Rproj`.

## Próximos passos

- Revisar a cobertura histórica e publicar o JSON municipal de 2025
- Definir o formato de publicação dos dados metropolitanos
- Refatorar código e usar {renv}
