# PEMOB

Pipeline em R que harmoniza os dados municipais e metropolitanos da PEMOB
(Pesquisa Nacional de Mobilidade Urbana) de 2019 a 2025. O
[roteiro](ROADMAP.md) registra prioridades, decisões e situação atual.

## Uso

```sh
Rscript -e 'renv::restore()'  # instala as versões fixadas em renv.lock
Rscript tests/test-pemob.R    # testes
Rscript R/build_pemob.R       # reconstrói 2019–2025 a partir dos arquivos originais
Rscript R/pemob_dataverse.R   # prepara os arquivos locais para o Dataverse
```

`R/build_pemob.R` roda `R/pemob.R` e `R/pemob_metropolitana.R`, que gravam os
históricos de 2019 a 2024 em `data/`, e depois `R/pemob_2025.R`, que acrescenta
2025. As saídas são `data/pemob_harmonizada_2025.csv` e
`data/pemob_metro_harmonizada_2025.csv`, com uma linha por local e edição e a
coluna `participated`. Por fim, `R/pemob_treatment.R` trata as séries de tarifa e
de infraestrutura cicloviária.

`R/pemob_dataverse.R` grava os arquivos longos municipais e metropolitanos,
participação, codebook, ledger de tratamentos e manifest em
`data/dataverse_draft/`. O manifest registra o commit, a situação do worktree
e os checksums. O arquivo é um rascunho local; a publicação no Dataverse
depende de revisão. `value_type` e `unit` ficam vazios até o registro de
perguntas ter metadados revisados. `parsed_unit` guarda apenas a unidade
escrita na resposta. `missing_code = blank` identifica uma célula vazia;
`value_raw` mantém o texto literal `NA` quando ele aparece na fonte. As linhas
interpoladas de edições sem participação têm `participated = FALSE` e
`value_raw` vazio.
O exportador só substitui um diretório existente quando encontra o marcador
do rascunho, os arquivos esperados e checksums válidos no manifest. Ele
recusa diretórios do projeto e dos insumos.

Em 2019, cada opção das perguntas de múltipla escolha vinha numa coluna própria.
O pipeline junta as opções marcadas com "Sim" numa única resposta. Quando outra
opção da mesma pergunta traz um código de ausência, como "NR", a resposta fica
listada em `data/pemob_range_incomplete.csv` e
`data/pemob_metro_range_incomplete.csv`, com as opções sem resposta.

## Estrutura

- `R/pemob.R`, `R/pemob_metropolitana.R`: leitura das edições, compatibilização
  dos códigos de perguntas e junção dos municípios e regiões.
- `R/build_pemob.R`: ponto de entrada do pipeline.
- `R/pemob_2025.R`: leitura dos CSVs de 2025 e junção ao histórico.
- `R/pemob_helpers.R`, `R/pemob_series.R`: leitura das respostas, missing
  reasons, parsing de valores e camada de revisão.
- `R/pemob_review.R`: candidatos a revisão de tarifas e infraestrutura
  cicloviária.
- `R/pemob_treatment.R`: aplica as decisões de revisão e preenche lacunas de
  uma edição nas tarifas e na infraestrutura cicloviária. Grava
  `data/pemob_target_treated.csv`, com status para cada célula, a contagem
  por status e o erro da validação por mascaramento.
- `R/pemob_dataverse.R`: prepara os arquivos locais da Fase 4 a partir do
  rebuild e do tratamento.
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
- O `renv` fixa os pacotes listados em `DESCRIPTION`, que cobrem o build e os
  testes. Os scripts antigos do portal usam pacotes fora dessa lista.
- Projeto RStudio: `simu_pemob.Rproj`.
