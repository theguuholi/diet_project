# 🥗 NutriBot
## Plano de Desenvolvimento — V1.0

**Aplicativo de controle nutricional com IA via WhatsApp**

Elixir · Phoenix · LiveView · Oban · Claude API · Gigalixir

_Abril 2026_

---

# 1. Visão Geral do Produto

O NutriBot é um assistente nutricional inteligente que opera primariamente via WhatsApp, permitindo que o usuário registre refeições com foto, áudio ou texto e receba instantaneamente o cálculo de calorias e macronutrientes. O produto é inspirado no Dieta.ai, mas construído sobre uma stack Elixir/Phoenix que oferece maior estabilidade, menor custo de infra e escalabilidade nativa.

## 1.1 Stack Tecnológica

| Camada | Tecnologia | Justificativa |
|---|---|---|
| Backend | Elixir + Phoenix 1.7 | Concorrência nativa, fault-tolerance, baixo custo de infra |
| Painel Web | Phoenix LiveView | Real-time sem JS complexo, UX fluida |
| Filas de Mídia | Oban Pro | Processamento robusto de fotos/áudios com retries |
| Banco de Dados | PostgreSQL via Gigalixir | Gerenciado, backups automáticos |
| IA (visão/texto) | Claude API (claude-sonnet) | Reconhecimento de alimentos por foto e texto |
| IA (áudio) | OpenAI Whisper API | Transcrição de áudios de refeição |
| Object Storage | Cloudflare R2 | Fotos/áudios, gratuito até 10GB, CDN global |
| Infra / Deploy | Gigalixir | Deploy nativo Elixir, hot upgrades, clustering |
| Bot WhatsApp | WhatsApp Business API | Canal principal de interação com o usuário |
| Autenticação | Pow + Pow Assent | Auth local + OAuth (Google/Apple) |
| Monitoramento | AppSignal ou Sentry | Erros, performance, alertas |

## 1.2 Princípios Arquiteturais

- **Contexts separados por domínio (Accounts, Nutrition, Tracking, Notifications, Integrations)**
- **Tudo que envolve mídia passa pelo Oban — nunca síncrono no request**
- **WhatsApp como canal primário, LiveView como painel secundário**
- **Feature flags desde o início pra lançar incrementalmente**
- **Testes desde o início: ExUnit + Mox pra dependências externas (Claude API, Whisper, WhatsApp)**

---

# 2. Fases de Desenvolvimento

O desenvolvimento está dividido em 4 fases progressivas. A Fase 1 entrega o MVP funcional e monetizável. As fases seguintes adicionam integrações e features avançadas.

---

## Fase 1 — MVP (Semanas 1–8)

**Objetivo:** produto funcional, com WhatsApp operando, IA calculando macros, painel web básico e assinatura ativa.

### Feature 1.1 — Onboarding via WhatsApp

O usuário inicia uma conversa com o bot, que coleta dados básicos: nome, peso, altura, % gordura, objetivo (emagrecer / manter / ganhar massa) e nível de atividade. O sistema calcula automaticamente TMB, TDEE e metas de macronutrientes.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Criar bot WhatsApp com flow de onboarding (FSM via GenServer) | 3 dias | P0 |
| Contexto Accounts: User, Profile, Goals | 2 dias | P0 |
| Cálculo automático de TMB (Katch-McArdle) e TDEE | 1 dia | P0 |
| Persistência das metas de macros no perfil | 1 dia | P0 |
| Testes unitários do cálculo nutricional | 1 dia | P0 |

### Feature 1.2 — Registro de Refeição por Texto

Usuário envia mensagem de texto livre ('comi 2 ovos com pão e queijo'). A Claude API interpreta, identifica alimentos e quantidades estimadas, retorna JSON estruturado com calorias e macros. O sistema persiste e atualiza o saldo do dia.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Integração com Claude API (HTTP client Req) | 1 dia | P0 |
| Prompt engineering para extração de alimentos e macros | 2 dias | P0 |
| Contexto Nutrition: Meal, FoodItem, MacroLog | 2 dias | P0 |
| Oban Job: ProcessTextMeal | 1 dia | P0 |
| Resposta formatada ao usuário via WhatsApp | 1 dia | P0 |
| Testes com Mox para Claude API | 1 dia | P0 |

### Feature 1.3 — Registro de Refeição por Foto

Usuário envia foto do prato. A imagem é armazenada no Cloudflare R2 e processada de forma assíncrona via Oban. A Claude API (vision) analisa a imagem, identifica alimentos visíveis e estima porções. O resultado é enviado de volta ao usuário com opção de confirmar ou corrigir.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Upload de imagem para Cloudflare R2 (ExAws ou HTTP direto) | 2 dias | P0 |
| Oban Job: ProcessImageMeal | 1 dia | P0 |
| Integração Claude API com vision (base64 image) | 2 dias | P0 |
| Flow de confirmação: bot pergunta se está correto | 2 dias | P0 |
| Correção manual de quantidade pelo usuário | 1 dia | P1 |

### Feature 1.4 — Registro de Refeição por Áudio

Usuário envia áudio descrevendo o que comeu. O arquivo é enviado para a API Whisper da OpenAI para transcrição. O texto transcrito é então processado pela Claude API, igual ao fluxo de texto.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Upload de áudio para R2 | 1 dia | P0 |
| Oban Job: TranscribeAudio (Whisper API) | 2 dias | P0 |
| Pipeline: áudio → texto → Claude → macros | 1 dia | P0 |
| Tratamento de erros de transcrição | 1 dia | P1 |

### Feature 1.5 — Saldo Calórico Diário

A qualquer momento o usuário pode perguntar 'quanto ainda posso comer?' ou 'meu resumo de hoje'. O bot responde com um resumo formatado mostrando o que já consumiu vs. a meta, separado por calorias, proteína, carboidrato e gordura.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Query agregada de macros do dia (por user_id + date) | 1 dia | P0 |
| Formatação da resposta WhatsApp com emojis e barras de progresso | 1 dia | P0 |
| Comando '/resumo' e intent detection via Claude | 1 dia | P0 |

### Feature 1.6 — Painel Web (LiveView)

Interface web acessível pelo celular mostrando o resumo do dia em tempo real, histórico da semana e metas de macros com barras de progresso visuais.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Auth via link mágico enviado pelo WhatsApp | 2 dias | P0 |
| Dashboard LiveView: macros do dia em tempo real | 3 dias | P0 |
| Gráfico semanal de calorias (LiveView + Chart.js) | 2 dias | P1 |
| Lista de refeições do dia com opção de deletar | 1 dia | P1 |
| PWA: manifest.json + service worker básico | 1 dia | P1 |

### Feature 1.7 — Assinatura e Pagamento

Plano de assinatura mensal/anual. Integração com Stripe (ou PagSeguro/Asaas para Brasil). Usuário sem assinatura ativa tem limite de 3 registros/dia como trial.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Contexto Billing: Subscription, Plan, Invoice | 2 dias | P0 |
| Integração Stripe Checkout ou Asaas | 3 dias | P0 |
| Webhook de pagamento confirmado → ativa assinatura | 1 dia | P0 |
| Middleware de feature gate (assinante vs. free) | 1 dia | P0 |
| Cancelamento via WhatsApp ou painel web | 1 dia | P1 |

---

## Fase 2 — Tracking Avançado (Semanas 9–14)

### Feature 2.1 — Registro de Exercícios

Usuário registra atividades físicas manualmente via WhatsApp ou painel. O sistema calcula calorias gastas e atualiza o TDEE do dia.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Contexto Tracking: Exercise, ActivityLog | 2 dias | P1 |
| Tabela de MET values para cálculo de gasto calórico | 2 dias | P1 |
| Reconhecimento de exercício por texto via Claude | 1 dia | P1 |
| Integração no saldo calórico diário | 1 dia | P1 |

### Feature 2.2 — Controle de Água

Usuário registra copos de água via WhatsApp ('tomei 2 copos'). O bot acompanha o total diário e envia alertas quando está abaixo da meta.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| WaterLog model e contexto | 1 dia | P1 |
| Comando de registro e consulta via WhatsApp | 1 dia | P1 |
| Meta diária configurável (padrão: 3L) | 1 dia | P2 |

### Feature 2.3 — Registro Corporal

Usuário registra peso, circunferências e % gordura. Gráficos de evolução no painel web. Cálculo automático de % gordura via foto usando Claude API (análise corporal).

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| BodyMeasurement model (peso, cintura, quadril, braço, etc.) | 2 dias | P1 |
| Gráfico de evolução de peso no LiveView | 2 dias | P1 |
| Análise corporal via foto com Claude API | 3 dias | P2 |

### Feature 2.4 — Timer de Jejum

Usuário inicia e encerra jejum via WhatsApp. O bot mostra quanto tempo de jejum já completou e envia notificação quando atingir a meta.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| FastingSession model com start/end timestamps | 1 dia | P2 |
| Comandos: /jejum iniciar, /jejum encerrar, /jejum status | 2 dias | P2 |
| Notificação automática ao atingir meta de horas | 1 dia | P2 |

### Feature 2.5 — Lembretes Personalizáveis

Usuário configura lembretes via WhatsApp (ex: 'me lembra de beber água todo dia às 10h, 14h e 18h'). Sistema usa Oban Cron para disparar as notificações no horário certo.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Reminder model com cron expression | 1 dia | P1 |
| Parser de horários via linguagem natural (Claude) | 2 dias | P1 |
| Oban Cron job: SendReminder | 1 dia | P1 |
| Gestão de lembretes via WhatsApp (listar, deletar) | 1 dia | P2 |

### Feature 2.6 — Cadastro de Receitas

Usuário cadastra receitas próprias com ingredientes e porções. Ao registrar 'comi minha omelete', o sistema usa a receita cadastrada pra calcular os macros automaticamente.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Recipe e RecipeIngredient models | 2 dias | P2 |
| CRUD de receitas via painel web | 2 dias | P2 |
| Reconhecimento de receita salva ao registrar refeição | 2 dias | P2 |

### Feature 2.7 — Relatórios e Histórico

Relatórios semanais e mensais enviados automaticamente via WhatsApp. Painel web com gráficos de evolução de macros, calorias, peso e água.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Oban Job: WeeklyReportJob | 2 dias | P1 |
| Gráficos LiveView: macros semana, peso mês | 3 dias | P1 |
| Exportação CSV do histórico | 1 dia | P3 |

---

## Fase 3 — IA Avançada (Semanas 15–20)

### Feature 3.1 — Assistente Conversacional

Usuário pode fazer perguntas livres ao bot: 'o que posso comer no jantar pra bater minha proteína?', 'quais alimentos têm mais proteína e menos carboidrato?'. Claude responde com contexto do perfil e histórico do usuário.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Context builder: injeta perfil + resumo do dia no prompt | 2 dias | P1 |
| Intent detection: refeição vs. pergunta vs. comando | 2 dias | P1 |
| Sugestão de alimentos baseada no saldo restante | 2 dias | P2 |
| Histórico de conversa no contexto (últimas 10 msgs) | 1 dia | P2 |

### Feature 3.2 — Avaliação Glicêmica

A cada refeição registrada, o sistema calcula estimativa de índice glicêmico e carga glicêmica dos alimentos. Alerta para refeições com carga glicêmica elevada.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Base de dados de IG por alimento (TACO + USDA) | 3 dias | P2 |
| Cálculo de carga glicêmica por refeição | 2 dias | P2 |
| Alerta no WhatsApp para refeições de alto IG | 1 dia | P3 |

### Feature 3.3 — Aprendizado de Hábitos

O sistema aprende os alimentos mais frequentes do usuário e passa a sugerir itens mais rapidamente. Detecção de padrões: 'você costuma pular o café da manhã às segundas'.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Tabela de frequência de alimentos por usuário | 2 dias | P3 |
| Sugestão de alimentos frequentes no registro | 2 dias | P3 |
| Weekly insight: padrão detectado enviado via WhatsApp | 2 dias | P3 |

---

## Fase 4 — Integrações Externas (Semanas 21–28)

### Feature 4.1 — Integração Strava

Sincronização automática de atividades físicas do Strava. Exercícios registrados no Strava aparecem automaticamente no NutriBot e atualizam o saldo calórico do dia.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| OAuth2 com Strava (Assent) | 2 dias | P2 |
| Webhook Strava: atividade concluída → Oban Job | 2 dias | P2 |
| Mapeamento de tipo de atividade → calorias | 2 dias | P2 |

### Feature 4.2 — Integração Garmin / Apple Health / Whoop

Sincronização de dados de wearables via Strava como hub central (Garmin, Apple Watch, Whoop já integram com Strava). Dados de frequência cardíaca e calorias ativas enriquecem o cálculo de TDEE.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Processar payload Strava com dados de HR e calorias ativas | 2 dias | P2 |
| TDEE dinâmico baseado em dados do wearable | 3 dias | P3 |

### Feature 4.3 — Integração FreeStyle Libre

Importação de dados de glicemia do sensor FreeStyle Libre via LibreView API. Gráficos mostrando o impacto de cada refeição na glicemia ao longo do tempo.

| Tarefa | Estimativa | Prioridade |
|---|---|---|
| Integração LibreView API (OAuth2) | 3 dias | P3 |
| GlucoseReading model e importação histórica | 2 dias | P3 |
| Correlação refeição → pico glicêmico no LiveView | 3 dias | P3 |

---

# 3. Arquitetura de Contextos Phoenix

O projeto segue a arquitetura de contextos do Phoenix, separando claramente as responsabilidades de cada domínio. Cada contexto expõe uma API pública e os contextos não se chamam diretamente — comunicação via PubSub ou Oban Jobs quando necessário.

| Contexto | Responsabilidade | Principais Schemas |
|---|---|---|
| Accounts | Usuários, autenticação, perfis, assinaturas | User, Profile, Subscription |
| Nutrition | Refeições, alimentos, cálculo de macros, receitas | Meal, FoodItem, Recipe, MacroLog |
| Tracking | Exercícios, peso, água, jejum, medidas corporais | Exercise, WaterLog, BodyMeasurement, FastingSession |
| Notifications | Lembretes, relatórios, alertas via WhatsApp | Reminder, NotificationLog |
| Integrations | Strava, LibreLink, WhatsApp Business API | StravaToken, GlucoseReading |
| Bot | FSM do WhatsApp, intent detection, formatação de respostas | Conversation, ConversationState |
| AI | Wrapper da Claude API e Whisper API | — |
| Billing | Stripe/Asaas, planos, faturas | Plan, Invoice |

## 3.1 Fluxo de Processamento de Mídia

Todo processamento pesado (foto, áudio, chamada de IA) é assíncrono via Oban para garantir que o bot responda rapidamente ao usuário e não perca mensagens do WhatsApp por timeout.

| Etapa | Responsável | Detalhe |
|---|---|---|
| 1. Receber mensagem | BotController (Phoenix) | Webhook WhatsApp → responde 200 em < 2s |
| 2. Enfileirar job | Oban | ProcessMealJob com payload da mensagem |
| 3. Download de mídia | Oban Worker | Baixa foto/áudio do WhatsApp e salva no R2 |
| 4. Processar com IA | Oban Worker | Claude API (visão/texto) ou Whisper (áudio) |
| 5. Persistir resultado | Nutrition context | Salva Meal + MacroLog no banco |
| 6. Notificar usuário | Bot context | Envia resposta formatada via WhatsApp |

---

# 4. Cronograma Resumido

| Fase | Período | Entrega Principal | Status |
|---|---|---|---|
| Fase 1 — MVP | Semanas 1–8 | WhatsApp + IA + macros + painel + assinatura | 🟡 A iniciar |
| Fase 2 — Tracking | Semanas 9–14 | Exercícios, água, corpo, lembretes, receitas | ⚪ Planejado |
| Fase 3 — IA Avançada | Semanas 15–20 | Assistente, IG, aprendizado de hábitos | ⚪ Planejado |
| Fase 4 — Integrações | Semanas 21–28 | Strava, Garmin, FreeStyle Libre | ⚪ Planejado |

## 4.1 Estimativa de Custo Mensal (Pós-Lançamento)

| Serviço | Plano | Custo Estimado |
|---|---|---|
| Gigalixir | Standard (1 réplica) | ~$25/mês |
| PostgreSQL Gigalixir | 0.6 GB | ~$25/mês |
| Claude API | ~100k tokens/dia | ~$30–50/mês |
| Whisper API (OpenAI) | ~1h de áudio/dia | ~$10/mês |
| Cloudflare R2 | < 10GB storage | Gratuito |
| WhatsApp Business API | Meta Cloud API | ~$0,008/msg (pago por uso) |
| **Total estimado** | | **~$90–120/mês** |

> Com uma base de 200 assinantes pagando R$29,90/mês o produto já cobre os custos de infra com folga.
