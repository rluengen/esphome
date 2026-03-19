# ESP32 12V Motor Direction Controller — Single PCB Design

## System Overview

A single custom PCB that drives a 12V DC motor in both directions using two opto-isolated SPDT relays configured as an H-bridge, with an INA226 IC for high-side current sensing (external 1mΩ shunt, rated for 20A), and two low-voltage switch inputs. The **XIAO ESP32-S3** plugs into pin headers on the board, providing the MCU, WiFi, USB-C programming, and 3.3V regulation. An on-board TPS54302 buck converter steps 12V down to 5V to power the XIAO.

```
 ┌──────────────────────────────────────────────────────────────────────────────┐
 │                          SINGLE PCB                                         │
 │                                                                             │
 │  ┌─────────────┐    ┌─────────────┐    ┌───────┐    ┌──────┐   ┌──────┐    │
 │  │  TPS54302    │    │ XIAO        │    │INA226 │    │PC817A│   │RELAY │    │
 │  │  12V→5V    ─┼─5V─┤ ESP32-S3   ─┼─I2C─┤ IC   │    │ opto │──►│  A   │    │
 │  │  Buck Conv.  │    │  (socketed) │    │       │    └──────┘   └──────┘    │
 │  └──────┬───────┘    │  D2─SW1     │    │  ┌────┤                          │
 │         │            │  D3─SW2     │    │  │1mΩ │    ┌──────┐   ┌──────┐    │
 │    +12V─┼────────────│  D4─SDA     │    │  │shunt│    │PC817B│   │RELAY │    │
 │    GND──┼────────────│  D5─SCL     │    │  └────┤    │ opto │──►│  B   │    │
 │         │            │  D0─RLY_A   │    └───────┘    └──────┘   └──────┘    │
 │         │            │  D1─RLY_B   │                                        │
 │         │            │     USB-C   │    [MOTOR+]  [MOTOR-]  [SW1]  [SW2]    │
 │         │            └─────────────┘    [+12V IN]  [GND]                    │
 └──────────────────────────────────────────────────────────────────────────────┘
```

---

## ESP32 Module: Seeed Studio XIAO ESP32-S3 (Socketed)

The XIAO ESP32-S3 plugs into **female pin headers** soldered to the custom PCB. This means the XIAO can be removed for programming, replacement, or reuse. The XIAO provides the MCU, USB-C connector, boot/reset buttons, and on-board 3.3V LDO regulator — so the custom PCB doesn't need any of those.

| Spec | Value |
|------|-------|
| Module | Seeed Studio XIAO ESP32-S3 |
| MCU | ESP32-S3 (dual-core Xtensa LX7, 240 MHz) |
| Flash | 8 MB |
| PSRAM | 8 MB |
| WiFi | 2.4 GHz 802.11 b/g/n |
| BLE | Bluetooth 5.0 LE |
| GPIO Count | 11 usable (D0–D10) |
| I2C | GPIO5 (SDA / D4), GPIO6 (SCL / D5) |
| Operating Voltage | 3.3V logic, 5V power input |
| USB-C | Built-in (programming + power) |
| Boot/Reset | Built-in buttons |
| Size | 21 × 17.8 mm |
| Price | ~$7.49 USD |
| Purchase | [Seeed Studio](https://www.seeedstudio.com/XIAO-ESP32S3-p-5627.html) |

**Advantages of socketing the XIAO:**
- No need for USB-C connector, ESD protection, boot/reset buttons, or LDO on the PCB — the XIAO has all of these
- Easy to program via USB-C while docked
- Removable for debugging or replacement
- Well-documented ESPHome support (you already have `devices/xiao-esp32s3.yaml`)
- Antenna is at the board edge by default when socketed at a PCB edge

### GPIO Assignment (XIAO Pin Labels)

| XIAO Pin | GPIO | Function | Direction |
|----------|------|----------|-----------|
| D0 | GPIO1 | Relay A control (via optocoupler) | Output |
| D1 | GPIO2 | Relay B control (via optocoupler) | Output |
| D2 | GPIO3 | Switch 1 input | Input (pull-up) |
| D3 | GPIO4 | Switch 2 input | Input (pull-up) |
| D4 | GPIO5 | I2C SDA (INA226) | Bidirectional |
| D5 | GPIO6 | I2C SCL (INA226) | Bidirectional |
| 5V | — | Power input from TPS54302 (5V) | Power |
| GND | — | Common ground | Power |

---

## Complete Bill of Materials (PCB Components)

### 1. XIAO ESP32-S3 + Socket

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| U1 | Seeed Studio XIAO ESP32-S3 | Castellated / pin header | 8MB flash, 8MB PSRAM, WiFi/BLE, USB-C | 1 | $7.49 | [Seeed Studio](https://www.seeedstudio.com/XIAO-ESP32S3-p-5627.html), [Amazon](https://www.amazon.com/dp/B0C69FFXHX), [DigiKey](https://www.digikey.com/en/products/detail/seeed-technology-co-ltd/113991114/18667880), [Mouser](https://www.mouser.com/ProductDetail/713-113991114) |
| J_XIAO | 2× 7-pin female pin header | 2.54mm pitch, THT | Socket for the XIAO module (7 pins per side) | 2 | $0.20 ea | [Amazon](https://www.amazon.com/s?k=2.54mm+female+pin+header), [LCSC](https://www.lcsc.com/search?q=female+pin+header+2.54mm), [AliExpress](https://www.aliexpress.com/w/wholesale-2.54mm-female-pin-header.html) |

### 2. Power: 12V → 5V Buck Converter (TPS54302)

The **TPS54302** steps 12V down to **5V** to power the XIAO's 5V input pin. The XIAO's on-board LDO then regulates 5V → 3.3V for the ESP32-S3 and logic ICs.

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| U2 | TPS54302DDCR | SOT-23-6 | 4.5–28V in, adjustable out, 3A, synchronous buck, 570kHz | 1 | $1.10 | [Mouser](https://www.mouser.com/ProductDetail/595-TPS54302DDCR), [DigiKey](https://www.digikey.com/en/products/detail/texas-instruments/TPS54302DDCR/5765168), [LCSC](https://www.lcsc.com/product-detail/DC-DC-Converters_Texas-Instruments-TPS54302DDCR_C130094.html) |
| L1 | 10µH inductor | 5×5mm or 6×6mm shielded | ≥3A saturation, <100mΩ DCR, e.g. Bourns SRN5040-100M | 1 | $0.30 | [Mouser](https://www.mouser.com/c/passive-components/inductors/?q=SRN5040-100M), [DigiKey](https://www.digikey.com/en/products/filter/fixed-inductors/71?s=SRN5040-100M), [LCSC](https://www.lcsc.com/search?q=10uH+shielded+inductor+5x5) |
| C1 | 22µF 25V ceramic capacitor | 1210 | Input capacitor (X5R or X7R) | 1 | $0.15 | [LCSC](https://www.lcsc.com/search?q=22uF+25V+1210), [DigiKey](https://www.digikey.com/en/products/filter/ceramic-capacitors/60?s=22uF+25V+1210), [Mouser](https://www.mouser.com/c/passive-components/capacitors/ceramic-capacitors/?q=22uF%2025V%201210) |
| C2a, C2b | 22µF 10V ceramic capacitor | 0805 or 1206 | Output capacitors (X5R or X7R) | 2 | $0.10 ea | [LCSC](https://www.lcsc.com/search?q=22uF+10V+0805), [DigiKey](https://www.digikey.com/en/products/filter/ceramic-capacitors/60?s=22uF+10V+0805), [Mouser](https://www.mouser.com/c/passive-components/capacitors/ceramic-capacitors/?q=22uF%2010V%200805) |
| C3 | 100nF ceramic capacitor | 0402 or 0603 | BOOT capacitor (BST to SW pin) | 1 | $0.02 | [LCSC](https://www.lcsc.com/search?q=100nF+0603), [DigiKey](https://www.digikey.com/en/products/filter/ceramic-capacitors/60?s=100nF+0603), [Mouser](https://www.mouser.com/c/passive-components/capacitors/ceramic-capacitors/?q=100nF%200603) |
| R1 | 100kΩ resistor | 0402 or 0603 | EN pull-up to VIN (always-on) | 1 | $0.01 | [LCSC](https://www.lcsc.com/search?q=100k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=100k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=100k%200603) |
| R2 | 73.2kΩ resistor | 0402 or 0603 | Top feedback resistor (sets 5V) | 1 | $0.01 | [LCSC](https://www.lcsc.com/search?q=73.2k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=73.2k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=73.2k%200603) |
| R3 | 10kΩ resistor | 0402 or 0603 | Bottom feedback resistor (sets 5V) | 1 | $0.01 | [LCSC](https://www.lcsc.com/search?q=10k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=10k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=10k%200603) |

**Output voltage calculation:**

$$V_{OUT} = V_{REF} \times \left(1 + \frac{R2}{R3}\right) = 0.596V \times \left(1 + \frac{73.2k\Omega}{10k\Omega}\right) = 0.596 \times 8.32 = 4.96V \approx 5.0V$$

#### TPS54302 Reference Circuit (5V Output)

```
                           TPS54302 (SOT-23-6)
                         ┌──────────────────┐
 +12V ──┬──[22µF C1]──┬─┤ VIN(1)    BST(6) ├──[100nF C3]──┐
        │     GND      │ │                  │              │
        │         [100kΩ]┤ EN(3)     SW(5)  ├──────────────┼──┬──[10µH L1]──┬── 5V OUT
        │                │                  │                │              │
        └────────────────┤ GND(2)    FB(4)  ├──┐             │           ┌──┴──┐
                   GND   └──────────────────┘  │             │           │22µF │ ×2
                                               │             │           │ C2  │
                                          ┌────┘             │           └──┬──┘
                                          │                  │              │
                                     ┌────┴────┐             │             GND
                                     │  73.2kΩ │ R2          │
                                     └────┬────┘           GND
                                          │
                                     ┌────┴────┐
                                     │  10kΩ   │ R3
                                     └────┬────┘
                                          │
                                         GND

 5V OUT ──→ XIAO 5V pin (powers XIAO + its on-board 3.3V LDO)
 XIAO 3.3V pin ──→ INA226 VCC, I2C pull-ups
```

### 3. INA226 Current Sensor IC

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| U3 | INA226AIDGSR | MSOP-10 | 16-bit ADC, I2C, ±81.92mV shunt range, 0.33mA quiescent | 1 | $2.80 | [Mouser](https://www.mouser.com/ProductDetail/595-INA226AIDGSR), [DigiKey](https://www.digikey.com/en/products/detail/texas-instruments/INA226AIDGSR/2770693), [LCSC](https://www.lcsc.com/product-detail/Current-Voltage-Power-Monitor-ICs_Texas-Instruments-INA226AIDGSR_C138706.html) |
| R_SHUNT | 1mΩ current sense resistor | 2512 (4-terminal Kelvin) | ±1%, 5W, e.g. Bourns CSS2H-2512R-L1FE or Ohmite LVK12R001DER | 1 | $1.50 | [Mouser](https://www.mouser.com/c/passive-components/resistors/current-sense-resistors/?q=1mohm%202512%205W), [DigiKey](https://www.digikey.com/en/products/filter/current-sense-resistors/54?s=1mohm+2512+5W), [LCSC](https://www.lcsc.com/search?q=1mohm+2512+current+sense) |
| C_INA | 100nF ceramic capacitor | 0402 or 0603 | Decoupling on INA226 VS pin | 1 | $0.02 | [LCSC](https://www.lcsc.com/search?q=100nF+0603), [DigiKey](https://www.digikey.com/en/products/filter/ceramic-capacitors/60?s=100nF+0603), [Mouser](https://www.mouser.com/c/passive-components/capacitors/ceramic-capacitors/?q=100nF%200603) |
| R_SDA | 4.7kΩ resistor | 0402 or 0603 | I2C SDA pull-up to 3.3V | 1 | $0.01 | [LCSC](https://www.lcsc.com/search?q=4.7k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=4.7k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=4.7k%200603) |
| R_SCL | 4.7kΩ resistor | 0402 or 0603 | I2C SCL pull-up to 3.3V | 1 | $0.01 | [LCSC](https://www.lcsc.com/search?q=4.7k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=4.7k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=4.7k%200603) |

**I2C Address:** A0 and A1 tied to GND → address **0x40**.

**Shunt specifications for 20A:**
- Shunt voltage at 20A: $V_{shunt} = 20A \times 1m\Omega = 20mV$ — well within ±81.92mV range
- Resolution (LSB): $2.5\mu V / 1m\Omega = 2.5mA$ per count
- Power dissipation at 20A: $P = I^2R = 400 \times 0.001 = 0.4W$ — well within 5W rating

#### INA226 Circuit (MSOP-10)

```
                              INA226 (MSOP-10)
                         ┌─────────────────────┐
         ┌───────────────┤ 1  A1        VS  10 ├──── 3.3V (from XIAO) ──[100nF C_INA]── GND
         │   ┌───────────┤ 2  A0       SCL   9 ├──── GPIO6 (D5) ──[4.7kΩ to 3.3V]
        GND GND          │                     │
                    (nc) ┤ 3  ALERT   SDA   8 ├──── GPIO5 (D4) ──[4.7kΩ to 3.3V]
                         │                     │
         GND ────────────┤ 4  GND    VBUS   7 ├──── 12V_SENSED (load side of shunt)
                         │                     │
                     ┌───┤ 5  INP    INN    6 ├───┐
                     │   └─────────────────────┘   │
                     │      (sense+)    (sense-)   │
                     │                             │
    ─────────────────┼─────────────────────────────┼───────
    CURRENT PATH:    │                             │
                     │    ┌──────────────────┐     │
    +12V IN ─────────┼────┤  1mΩ SHUNT (2512)├────┼────── 12V_SENSED (to relays)
                     │    │                  │     │
                     └────┤ Sense+    Sense− ├─────┘
                          │  (Kelvin pads)   │
                          └──────────────────┘

 ← Current direction →
 Heavy copper traces (≥2.5mm wide, 2oz copper) for the current path.
 Thin traces for Kelvin sense lines to INA226 INP/INN.
```

### 4. Relays

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| K1, K2 | SRD-12VDC-SL-C | Through-hole (PCB mount) | SPDT, 12V coil (~30mA, 400Ω), 10A contacts | 2 | $1.00 ea | [Amazon](https://www.amazon.com/s?k=SRD-12VDC-SL-C+relay), [AliExpress](https://www.aliexpress.com/w/wholesale-SRD-12VDC-SL-C.html), [LCSC](https://www.lcsc.com/search?q=SRD-12VDC-SL-C), [DigiKey](https://www.digikey.com/en/products/filter/power-relays/60?s=SRD-12VDC-SL-C) |

*For 20A motor loads, upgrade to 20A-rated relays: Omron G5CA-1A-12DC or similar. Same footprint.*

### 5. Opto-Isolated Relay Drivers (×2)

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| U4, U5 | EL817S1(C)(TU) or PC817 SMD | SOP-4 | CTR ≥50%, IF=10mA, VCE=35V | 2 | $0.10 ea | [LCSC](https://www.lcsc.com/product-detail/Optocouplers_Everlight-Elec-EL817S1-C-TU_C106900.html), [DigiKey](https://www.digikey.com/en/products/filter/optoisolators/44?s=EL817), [Mouser](https://www.mouser.com/c/optoelectronics/optocouplers/?q=EL817) |
| Q1, Q2 | MMBT2222A | SOT-23 | NPN, VCE=40V, IC=600mA, hFE≥100 | 2 | $0.03 ea | [LCSC](https://www.lcsc.com/search?q=MMBT2222A), [DigiKey](https://www.digikey.com/en/products/filter/transistors-bipolar-bjt/41?s=MMBT2222A), [Mouser](https://www.mouser.com/c/semiconductors/discrete-semiconductors/transistors/bipolar-bjt/?q=MMBT2222A) |
| D1, D2 | SS14 (SMD Schottky) | SMA | 40V 1A — flyback diode across relay coil | 2 | $0.03 ea | [LCSC](https://www.lcsc.com/search?q=SS14+SMA), [DigiKey](https://www.digikey.com/en/products/filter/diodes-rectifiers/45?s=SS14), [Mouser](https://www.mouser.com/c/semiconductors/discrete-semiconductors/diodes-rectifiers/schottky-diodes/?q=SS14) |
| R4, R5 | 220Ω | 0402 or 0603 | PC817 LED current limiter ($I_F \approx 9.5mA$) | 2 | $0.01 ea | [LCSC](https://www.lcsc.com/search?q=220ohm+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=220+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=220ohm%200603) |
| R6, R7 | 4.7kΩ | 0402 or 0603 | 12V pull-up / MMBT2222A base drive | 2 | $0.01 ea | [LCSC](https://www.lcsc.com/search?q=4.7k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=4.7k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=4.7k%200603) |
| R8, R9 | 10kΩ | 0402 or 0603 | Base-emitter pull-down (ensures OFF) | 2 | $0.01 ea | [LCSC](https://www.lcsc.com/search?q=10k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=10k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=10k%200603) |

#### Opto-Isolated Driver Circuit (per channel, ×2)

```
 3.3V ISOLATED DOMAIN                ┃    12V POWER DOMAIN
                                     ┃
 XIAO GPIO1 (D0) or GPIO2 (D1)     ┃         +12V
      │                              ┃          │
      │    ┌────────────┐            ┃       ┌──┴──┐
      ├──[220Ω]──┤1A  PC817  4C├─────╂──[4.7kΩ]──┤Relay│
      │          │  SOP-4 ►◄  │     ┃    │    │Coil │
 XIAO GND ──────┤2K       3E├──┐  ┃    │    └──┬──┘
                 └────────────┘   │  ┃    │    ┌──┴──┐
                                  │  ┃    │    │SS14 │ (cathode to +12V)
                                  │  ┃    │    └──┬──┘
                                  │  ┃    └───────┤
                                  │  ┃            │
                                  │  ┃     ┌──────┘
                                  │  ┃     │
                                  │  ┃   ┌─┴─┐
                                  │  ┃   │ C │ MMBT2222A (SOT-23)
                                  │  ┃   │   │
                                  └──╂──[10kΩ]──┤ B │
                                     ┃   │   │
                                     ┃   │ E │
                                     ┃   └─┬─┘
                                     ┃     │
                                     ╂─────┴──── 12V GND
```

**Current calculations:**
- PC817 LED: $(3.3V - 1.2V) / 220\Omega = 9.5mA$ — within ESP32-S3 GPIO limit (40mA)
- Relay coil: $12V / 400\Omega = 30mA$ — within MMBT2222A's 600mA rating
- $h_{FE} \geq 100 \Rightarrow I_B$ needed = $0.3mA$ — satisfied by driver circuit

### 6. Switch Inputs

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| J_SW | 4-pin header or JST-XH | 2.54mm pitch, THT or SMD | SW1, GND, SW2, GND | 1 | $0.20 | [Amazon](https://www.amazon.com/s?k=JST-XH+4+pin+connector), [LCSC](https://www.lcsc.com/search?q=JST+XH+4pin), [AliExpress](https://www.aliexpress.com/w/wholesale-jst-xh-4-pin.html) |
| C_SW1, C_SW2 | 100nF ceramic capacitor | 0402 or 0603 | Hardware debounce | 2 | $0.02 ea | [LCSC](https://www.lcsc.com/search?q=100nF+0603), [DigiKey](https://www.digikey.com/en/products/filter/ceramic-capacitors/60?s=100nF+0603), [Mouser](https://www.mouser.com/c/passive-components/capacitors/ceramic-capacitors/?q=100nF%200603) |
| R_SW1, R_SW2 | 10kΩ resistor | 0402 or 0603 | External pull-up to 3.3V | 2 | $0.01 ea | [LCSC](https://www.lcsc.com/search?q=10k+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=10k+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=10k%200603) |

```
 3.3V (from XIAO)               3.3V (from XIAO)
  │                               │
 [10kΩ R_SW1]                  [10kΩ R_SW2]
  │                               │
  ├── GPIO3 (D2)                  ├── GPIO4 (D3)
  │                               │
 [100nF C_SW1]                 [100nF C_SW2]
  │                               │
  ├── SW1 Pin ──→ J_SW            ├── SW2 Pin ──→ J_SW
  │                               │
 GND                             GND
```

### 7. Decoupling & Bypass

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| C_3V3 | 10µF ceramic capacitor | 0805 | Bulk decoupling on 3.3V rail (near XIAO 3.3V pin) | 1 | $0.05 | [LCSC](https://www.lcsc.com/search?q=10uF+0805+ceramic), [DigiKey](https://www.digikey.com/en/products/filter/ceramic-capacitors/60?s=10uF+0805), [Mouser](https://www.mouser.com/c/passive-components/capacitors/ceramic-capacitors/?q=10uF%200805) |
| C_3V3b | 100nF ceramic capacitor | 0402 or 0603 | Local decoupling on 3.3V rail | 1 | $0.02 | [LCSC](https://www.lcsc.com/search?q=100nF+0603), [DigiKey](https://www.digikey.com/en/products/filter/ceramic-capacitors/60?s=100nF+0603), [Mouser](https://www.mouser.com/c/passive-components/capacitors/ceramic-capacitors/?q=100nF%200603) |

### 8. Connectors

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| J_PWR | 2-pos screw terminal | 5.08mm pitch, THT | +12V, GND — rated ≥20A | 1 | $0.50 | [Amazon](https://www.amazon.com/s?k=5.08mm+2+pin+screw+terminal), [LCSC](https://www.lcsc.com/search?q=5.08mm+2P+screw+terminal), [AliExpress](https://www.aliexpress.com/w/wholesale-5.08mm-2-pin-screw-terminal.html), [DigiKey](https://www.digikey.com/en/products/filter/terminal-blocks/40?s=5.08mm+2+position) |
| J_MOT | 2-pos screw terminal | 5.08mm pitch, THT | Motor +, Motor − — rated ≥20A | 1 | $0.50 | [Amazon](https://www.amazon.com/s?k=5.08mm+2+pin+screw+terminal), [LCSC](https://www.lcsc.com/search?q=5.08mm+2P+screw+terminal), [AliExpress](https://www.aliexpress.com/w/wholesale-5.08mm-2-pin-screw-terminal.html), [DigiKey](https://www.digikey.com/en/products/filter/terminal-blocks/40?s=5.08mm+2+position) |
| J_SW | 4-pin header / JST-XH | 2.54mm pitch | SW1, GND, SW2, GND | 1 | $0.20 | [Amazon](https://www.amazon.com/s?k=JST-XH+4+pin+connector), [LCSC](https://www.lcsc.com/search?q=JST+XH+4pin), [AliExpress](https://www.aliexpress.com/w/wholesale-jst-xh-4-pin.html) |

### 9. Status LED (Optional)

| Ref | Part | Package | Specification | Qty | Price | Source |
|-----|------|---------|---------------|-----|-------|--------|
| LED1 | Green LED | 0603 | Power indicator on 5V rail | 1 | $0.02 | [LCSC](https://www.lcsc.com/search?q=green+LED+0603), [DigiKey](https://www.digikey.com/en/products/filter/led-indication/105?s=green+0603+LED), [Mouser](https://www.mouser.com/c/optoelectronics/leds/?q=green%200603%20LED) |
| R_LED | 680Ω resistor | 0402 or 0603 | Current limiter ($I \approx 5mA$ from 5V) | 1 | $0.01 | [LCSC](https://www.lcsc.com/search?q=680ohm+0603+resistor), [DigiKey](https://www.digikey.com/en/products/filter/chip-resistor/52?s=680+0603), [Mouser](https://www.mouser.com/c/passive-components/resistors/chip-smd-resistors/?q=680ohm%200603) |

---

## Total Estimated Cost Per Board

| Section | Cost |
|---------|------|
| XIAO ESP32-S3 + socket headers | $7.89 |
| TPS54302 buck converter + passives | $1.85 |
| INA226 IC + shunt + passives | $4.35 |
| 2× Relays | $2.00 |
| 2× Opto-isolated drivers (all SMD) | $0.65 |
| Switch connectors + passives | $0.28 |
| Decoupling caps | $0.07 |
| Screw terminals (power + motor) | $1.00 |
| Status LED | $0.03 |
| **PCB fabrication (JLCPCB, 5 pcs)** | **~$5–8** |
| **Total per board (incl. PCB + XIAO)** | **~$24–30** |

*Without the XIAO (if you already have one): ~$16–22*

---

## H-Bridge Relay Motor Direction Control

```
                    12V_SENSED (from shunt load side)
                           │
              ┌────────────┼────────────┐
              │            │            │
         ┌────┴────┐  ┌───┴────┐  ┌────┴────┐
         │ Relay A │  │        │  │ Relay B │
         │   NO ◄──┘  │        │  └──► NC   │
         │   COM      │        │      COM   │
         │   NC ──►┐  │        │  ┌◄── NO   │
         └─────────┘  │        │  └─────────┘
              │        │        │        │
              │    MOTOR +  MOTOR -      │
              │                          │
              └────────── GND ───────────┘


 Direction Truth Table:
 ┌──────────┬──────────┬──────────────┬──────────────┬────────────┐
 │ Relay A  │ Relay B  │  Motor +     │  Motor -     │   State    │
 ├──────────┼──────────┼──────────────┼──────────────┼────────────┤
 │ OFF (NC) │ OFF (NC) │  GND         │  12V_SENSED  │ Direction A│
 │ ON  (NO) │ ON  (NO) │  12V_SENSED  │  GND         │ Direction B│
 │ OFF (NC) │ ON  (NO) │  GND         │  GND         │ Stopped    │
 │ ON  (NO) │ OFF (NC) │  12V_SENSED  │  12V_SENSED  │ Stopped    │
 └──────────┴──────────┴──────────────┴──────────────┴────────────┘
```

| Relay Pin | Connection |
|-----------|------------|
| Relay A — NO | 12V_SENSED (shunt load side) |
| Relay A — COM | Motor + terminal |
| Relay A — NC | Power GND |
| Relay B — NO | Power GND |
| Relay B — COM | Motor − terminal |
| Relay B — NC | 12V_SENSED (shunt load side) |

---

## Full Schematic — Block Level

```
                                    ┌─────────────────────────────────┐
                                    │       12V POWER DOMAIN          │
   +12V IN ──┬──────────────────────┼──→ [1mΩ SHUNT] ──→ 12V_SENSED ─┼─┬── K1 NO
             │                      │          │ INP           INN │   │ │
             │                      │          └─── INA226 IC ──┘   │   │ ├── K2 NC
             │                      │                    I2C ──────┼───┼─┤
             │                      │                              │   │ │
             │                      │   K1 COM ──→ MOTOR +         │   │ │
             │                      │   K2 COM ──→ MOTOR −         │   │ │
             │                      │                              │   │ │
             │                      │   K1 NC ──→ GND              │   │ │
             │                      │   K2 NO ──→ GND              │   │ │
             │                      │                              │   │ │
             │                      │   K1 Coil ←── Q1 ←─ U4 ─────┼───┘ │
             │                      │   K2 Coil ←── Q2 ←─ U5 ─────┼─────┘
             │                      └──────────────────────────────┘
             │
             │   ┌───────────────────────────────────────────────┐
             │   │           5V / 3.3V LOGIC DOMAIN              │
             │   │                                               │
             └───┼──→ TPS54302 (12V→5V) ──→ 5V Rail             │
                 │                            │                  │
                 │   ┌────────────────────────┼──┐               │
                 │   │   XIAO ESP32-S3        │  │               │
                 │   │   (socketed)           │  │               │
                 │   │                        │  │               │
                 │   │  5V  ◄─────────────────┘  │               │
                 │   │  3.3V ──→ INA226 VCC      │               │
                 │   │  GPIO1 (D0) ──→ U4 (PC817A) ──→ 12V      │
                 │   │  GPIO2 (D1) ──→ U5 (PC817B) ──→ 12V      │
                 │   │  GPIO3 (D2) ──← SW1          │            │
                 │   │  GPIO4 (D3) ──← SW2          │            │
                 │   │  GPIO5 (D4) ──→ INA226 SDA ──┼─[4.7kΩ]─ 3.3V
                 │   │  GPIO6 (D5) ──→ INA226 SCL ──┼─[4.7kΩ]─ 3.3V
                 │   │  USB-C (built-in)             │            │
                 │   └───────────────────────────────┘            │
                 │                                               │
   GND ──────────┼───────────────────────────────────────────────┘
                 └───────────────────────────────────────────────┘
```

---

## PCB Design Guidelines

### Layer Stack
- **2-layer PCB** is sufficient (4-layer preferred for better grounding and EMI)
- **Copper weight:** 2oz (70µm) — required for 20A current paths
- **Board size:** Approx. 80mm × 55mm (compact due to socketed XIAO)

### Layout Rules

1. **Power path traces (12V, motor, shunt):** ≥2.5mm wide on 2oz copper for 20A. Use copper pours where possible.
2. **Shunt Kelvin connection:** Route sense traces (INP/INN) as a thin, matched-length differential pair from the shunt's Kelvin pads to INA226. Keep away from high-current paths.
3. **Ground planes:** Use a solid ground pour on the bottom layer. Separate analog sense ground from power ground; join at a single star point near the input terminal.
4. **XIAO antenna clearance:** Place the XIAO socket at a board edge so the antenna end overhangs or is flush with the PCB edge. No ground pour or copper under/near the antenna end.
5. **Buck converter layout:** Keep VIN cap (C1), inductor (L1), and output caps (C2) physically close to the TPS54302. Minimize the SW node loop area (pin 5 → L1 → C2 → GND → pin 2).
6. **Decoupling caps:** Place C_3V3, C_3V3b close to the XIAO 3.3V pin. C_INA adjacent to INA226 VS pin.
7. **Thermal relief:** Add thermal vias under the shunt resistor pads for heat dissipation into the ground plane.
8. **Isolation gap:** Maintain ≥1mm clearance between 3.3V logic traces and 12V power traces. The optocouplers are the galvanic isolation boundary.
9. **Test points:** Add TPs for +12V, 5V, 3.3V, GND, SDA, SCL, and 12V_SENSED.
10. **XIAO USB-C access:** Ensure the USB-C port is accessible from the board edge for programming while docked.

### XIAO Socket Footprint

```
 ┌───────────────────┐
 │  XIAO ESP32-S3    │
 │                   │
 │  ●1  D0 (GPIO1)   │   ○  D10 (GPIO9)
 │  ●2  D1 (GPIO2)   │   ○  D9 (GPIO8)
 │  ●3  D2 (GPIO3)   │   ○  D8 (GPIO7)
 │  ●4  D3 (GPIO4)   │   ○  D7 (GPIO44)
 │  ●5  D4/SDA(GPIO5)│   ○  D6 (GPIO43)
 │  ●6  D5/SCL(GPIO6)│   ○  5V
 │  ●7  3V3          │   ○  GND
 │                   │
 │     [USB-C]       │  ◄── Place at board edge
 └───────────────────┘

 ● = Pins used by this design
 ○ = Available / power pins
```

Use **2× 7-pin female headers** (2.54mm pitch, through-hole) soldered to the PCB. The XIAO plugs in with its male castellated pads fitting into the headers.

### Recommended PCB Fabricator

| Fabricator | Min Order | 2-Layer Price (5 pcs) | Assembly (PCBA) |
|------------|-----------|----------------------|-----------------|
| JLCPCB | 5 pcs | ~$2 + shipping | SMT ~$8–15/board |
| PCBWay | 5 pcs | ~$5 + shipping | SMT available |
| OSH Park | 3 pcs | $5/sq inch | No assembly |

**JLCPCB PCBA workflow:** Upload Gerbers + BOM (with LCSC part numbers) + pick-and-place file. They solder all SMD components. You hand-solder through-hole parts (relays, screw terminals, XIAO socket headers).

---

## Power Budget

| Component | Voltage | Current | Source |
|-----------|---------|---------|--------|
| XIAO ESP32-S3 (WiFi TX peak) | 5V input → 3.3V internal | 200mA max from 5V | TPS54302 |
| INA226 IC | 3.3V (from XIAO) | 0.33mA | XIAO 3.3V LDO |
| I2C pull-ups (×2) | 3.3V | <1mA | XIAO 3.3V LDO |
| PC817 LEDs (×2, when active) | 3.3V (from GPIO) | 20mA total | XIAO 3.3V LDO |
| Switch pull-ups (×2) | 3.3V | <1mA | XIAO 3.3V LDO |
| Status LED | 5V | 5mA | TPS54302 |
| **Total from 5V** | | **~225mA max** | |
| Relay coils (×2, when energized) | 12V | 60mA total | 12V direct |
| MMBT2222A drivers (×2) | 12V | ~1mA total | 12V direct |
| Buck converter input (5V @ 225mA, ~90% eff.) | 12V | ~105mA | |
| **Total from 12V (excl. motor)** | | **~165mA** | |
| **Motor (application-dependent)** | 12V | **up to 20A** | Through shunt & relays |

The TPS54302 (3A at 5V) has massive headroom for the 225mA load.

**12V supply requirement:** 20A (motor) + 0.165A (board) = **20.2A minimum**.

---

## Safety Notes

1. **Never actuate only one relay** for motor driving — this creates a braking/short condition. Always switch both relays together (both ON or both OFF). Use the STOP state (one ON, one OFF) intentionally for braking.
2. **Add a fuse** on the 12V input — 20A or 25A fast-blow, or automotive blade fuse.
3. **Trace width:** ≥2.5mm for all 20A paths on 2oz copper. Verify with a [PCB trace width calculator](https://www.digikey.com/en/resources/conversion-calculators/conversion-calculator-pcb-trace-width).
4. **The INA226** with 1mΩ shunt can measure up to 81.92A. The relay contacts (10A) are the limit — upgrade to 20A relays if the motor exceeds 10A.
5. **Heat dissipation:** At 20A, shunt dissipates 0.4W (5W rated). No heatsink needed.
6. **Relay switching:** 50–100ms software delay between direction changes.
7. **Reverse polarity protection:** Consider a P-channel MOSFET (e.g., SI2301) on the 12V input.
8. **Do not power from USB and 12V simultaneously** unless you add diode isolation between the TPS54302 5V output and the XIAO 5V pin (e.g., a Schottky diode with cathode towards XIAO).

---

## ESPHome Configuration

The XIAO ESP32-S3 is already configured in your existing device package. The motor-controller.yaml references `devices/xiao-esp32s3.yaml` with the original XIAO GPIO pin mappings:

| XIAO Pin | GPIO | Function |
|----------|------|----------|
| D0 | GPIO1 | Relay A |
| D1 | GPIO2 | Relay B |
| D2 | GPIO3 | Switch 1 |
| D3 | GPIO4 | Switch 2 |
| D4 | GPIO5 | I2C SDA |
| D5 | GPIO6 | I2C SCL |

No GPIO changes needed from the original motor-controller.yaml — the XIAO pin mapping is the same.

---

## Design Files Checklist

To send this board for fabrication:

- [ ] **Schematic** — KiCad, EasyEDA, or Altium
- [ ] **PCB layout** — proper trace widths, keep-outs, Kelvin sense routing, XIAO socket footprint
- [ ] **BOM** — with LCSC part numbers for JLCPCB PCBA
- [ ] **Gerber files** — manufacturing output
- [ ] **Pick-and-place (CPL) file** — for JLCPCB SMT assembly
- [ ] **ESPHome YAML** — motor-controller.yaml (no changes needed)

**Recommended EDA:** [KiCad 8](https://www.kicad.org/) (free, open source) or [EasyEDA](https://easyeda.com/) (web-based, direct JLCPCB/LCSC integration).

**KiCad XIAO footprint:** Search for "XIAO" in the KiCad library, or use the [Seeed Studio KiCad library](https://github.com/Seeed-Studio/OPL_Kicad_Library) which includes the XIAO footprint.
