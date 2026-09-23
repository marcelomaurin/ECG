# Documentação de Hardware: Sistema de Monitoramento ECG com AD8232

Este documento descreve as especificações de hardware, diagrama de ligações, posicionamento de eletrodos e diretrizes de segurança elétrica para o projeto de eletrocardiograma (ECG) experimental.

---

> [!CAUTION]
> ### AVISO DE SEGURANÇA E USO EXPERIMENTAL / EDUCACIONAL
> - **ESTE DISPOSITIVO É UM PROTÓTIPO EXPERIMENTAL E EDUCACIONAL.**
> - **NÃO É UM EQUIPAMENTO MÉDICO OU DISPOSITIVO DE DIAGNÓSTICO CLÍNICO.**
> - Não utilize os dados deste equipamento para diagnóstico, triagem, tratamento médico ou tomada de decisões de saúde.
> - **ISOLAMENTO ELÉTRICO:** Ao conectar eletrodos ao corpo humano, garanta que o computador e o microcontrolador estejam operando com **bateria** (ex: notebook desconectado da tomada) ou através de um isolador USB médico certificado (isolamento galvânico mínimo de 4 kV), prevenindo qualquer risco de choque elétrico em caso de surtos na rede elétrica.

---

## 1. Componentes Utilizados

| Componente | Descrição / Modelo | Observações |
| :--- | :--- | :--- |
| **Microcontrolador** | Arduino Uno R3 / Nano / Pro Mini (ATmega328P) | Operação em 16 MHz, ADC de 10 bits (0–1023) |
| **Sensor de ECG** | Módulo AD8232 (Analog Devices) | Front-end analógico integrado de derivação única |
| **Cabos / Eletrodos** | Cabo de 3 vias com conector jack 3.5mm | Eletrodos descartáveis de Ag/AgCl com gel condutivo |
| **Alimentação** | 3.3V regulado fornecido pelo Arduino | **ATENÇÃO:** O AD8232 opera estritamente em **3.3V** |

---

## 2. Tabela de Ligações (Arduino <-> Módulo AD8232)

| Pino do Módulo AD8232 | Pino do Arduino | Função | Detalhes |
| :---: | :---: | :--- | :--- |
| **3.3V** | **3.3V** | Alimentação | **NUNCA** ligue no 5V (risco de queima do AD8232) |
| **GND** | **GND** | Terra Comum | Referência elétrica do circuito |
| **OUTPUT** | **A0** | Sinal Analógico | Sinal de ECG amplificado e filtrado (0 a 3.3V) |
| **LO+** | **Pino 10** | Leads-Off Detection (+) | Nível ALTO (1) se eletrodo positivo estiver desconectado |
| **LO-** | **Pino 11** | Leads-Off Detection (-) | Nível ALTO (1) se eletrodo negativo estiver desconectado |
| **SDN** | *(Não conectado)* | Shutdown | Deixar flutuando ou conectado a 3.3V para operação contínua |

---

## 3. Posicionamento Básico dos Eletrodos (Configuração de 3 Derivações)

O sistema utiliza a derivação I simplificada (Einhtoven) com três eletrodos de superfície:

```text
               (RA / Vermelho)           (LA / Amarelo)
              Clavícula Direita        Clavícula Esquerda
                      \                     /
                       \     [ CORAÇÃO ]   /
                        \                 /
                         \               /
                          (RL / Verde)
                        Costela Inferior
                            Direita
```

1. **RA (Right Arm / Vermelho):**
   - Posicionado próximo à clavícula direita (abaixo do ombro direito) ou no punho direito.
2. **LA (Left Arm / Amarelo):**
   - Posicionado próximo à clavícula esquerda (abaixo do ombro esquerdo) ou no punho esquerdo.
3. **RL (Right Leg / Verde):**
   - Eletrodo de referência (Right Leg Drive / Terra). Posicionado sobre a costela inferior direita ou quadril/tornozelo direito.

### Dicas para Aquisição com Baixo Ruído
- Higienizar a pele com álcool isopropílico 70% e secar completamente antes de aplicar os eletrodos descartáveis.
- Manter o paciente relaxado e imóvel durante a medição para mitigar ruídos eletromiográficos (EMG - contrações musculares).
- Evitar proximidade com cabos de alimentação de 110V/220V, carregadores de celular chaveados e monitores sem aterramento.
