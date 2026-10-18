# PEMOB

Pipeline em R que harmoniza os dados municipais e metropolitanos da PEMOB
(Pesquisa Nacional de Mobilidade Urbana) de 2019 a 2025. O
[roteiro](ROADMAP.md) registra prioridades, decisões e situação atual.

## Uso

```sh
Rscript tests/test-pemob.R          # testes
Rscript R/pemob.R                   # histórico municipal 2019–2024
Rscript R/pemob_metropolitana.R     # histórico metropolitano 2019–2024
Rscript R/pemob_2025.R              # acrescenta 2025
```

Os três scripts gravam CSVs em `data/`. `R/pemob_2025.R` acrescenta 2025 à
planilha harmonizada de 2024 em `tabelas/`, não ao histórico reconstruído.

## Estrutura

- `R/pemob.R`, `R/pemob_metropolitana.R`: leitura das edições, compatibilização
  dos códigos de perguntas e junção dos municípios e regiões.
- `R/pemob_2025.R`: leitura dos CSVs de 2025 e junção ao histórico.
- `R/pemob_helpers.R`, `R/pemob_series.R`: leitura das respostas, missing
  reasons, parsing de valores e camada de revisão.
- `R/pemob_review.R`, `R/pemob_interpolation.R`: candidatos a revisão e a
  interpolação de tarifas e infraestrutura cicloviária.
- `R/pemob_final.R`, `R/pemob_portal.R`, `R/pemob_portal_final.R`,
  `R/pemob_data_portal.R`: cálculos e exportações antigas do portal. Dependem
  de arquivos que não estão no repositório.
- `data-raw/`: arquivos originais da PEMOB.
- `tabelas/`: mapa de códigos das perguntas e planilha harmonizada de 2024.
- `data/`: dicionários e saídas geradas.
- `docs/internal/`: revisões, logs e planos de trabalho.

O dashboard e a tabela do [Observatório](https://observatorio.insper.edu.br/projetos/dashboard)
leem arquivos próprios no repositório `observatorio`, não as saídas de
`data/portal/v1/`.

## Notas

- Arquivos grandes ficam fora do controle de versão; ver `.gitignore`.
- Projeto RStudio: `simu_pemob.Rproj`.
