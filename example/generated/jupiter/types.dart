// GENERATED CODE - DO NOT MODIFY BY HAND
// Source: OpenAPI 3.0.3
// Swap API V2 2.0.0
//
// toJson contract (config-driven): every `toJson` takes an optional
// `JsonifyConfig` (`config`, default `DefaultJsonifyConfig.defaultConfig`) and
// returns the result through `config.encodeMap`, so `toJson` never
// returns null — it always yields a Map.
// BigInt / null handling is delegated to the config: `encodeBigint`
// encodes BigInt values and `encodeMap` post-processes the map.
// Make sure the configured output is `jsonEncode`-compatible: raw
// BigInt values are rejected by `jsonEncode`, so either keep the
// default string encoding or handle BigInt in your own encoder.

import 'package:blockchain_utils/blockchain_utils.dart';

class JupiterInstruction {
  /// Program executing the instruction
  final String programId;
  final List<JupiterInstructionAccountsItem> accounts;

  /// Base64-encoded instruction data
  final String data;

  const JupiterInstruction({
    required this.programId,
    required this.accounts,
    required this.data,
  });

  factory JupiterInstruction.fromJson(Map<String, dynamic> json) {
    return JupiterInstruction(
      programId: (json['programId'] is num
          ? json['programId'].toString()
          : json.valueAsString<String>('programId')),
      accounts: json
          .valueEnsureAsList<Map<String, dynamic>>('accounts')
          .map((e) => JupiterInstructionAccountsItem.fromJson(e))
          .toList(),
      data: (json['data'] is num
          ? json['data'].toString()
          : json.valueAsString<String>('data')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'programId': programId,
    'accounts': accounts.map((e) => e.toJson(config: config)).toList(),
    'data': data,
  });
}

class JupiterPlatformFee {
  final String? amount;

  /// Jupiter platform fee component in basis points. This is the fee Jupiter intends to make from the swap and does not include gasless support cost recoup.
  final num? feeBps;
  final String? feeMint;

  const JupiterPlatformFee({this.amount, this.feeBps, this.feeMint});

  factory JupiterPlatformFee.fromJson(Map<String, dynamic> json) {
    return JupiterPlatformFee(
      amount: (json['amount'] is num
          ? json['amount'].toString()
          : json.valueAsString<String?>('amount')),
      feeBps: json.valueAsNum<num?>('feeBps'),
      feeMint: (json['feeMint'] is num
          ? json['feeMint'].toString()
          : json.valueAsString<String?>('feeMint')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'amount': amount,
    'feeBps': feeBps,
    'feeMint': feeMint,
  });
}

class JupiterRoutePlanStep {
  final JupiterSwapInfo swapInfo;

  /// Percentage of total swap routed through this step
  final num percent;

  /// Basis points of total swap routed through this step
  final num bps;

  /// USD value of this step
  final num? usdValue;

  const JupiterRoutePlanStep({
    required this.swapInfo,
    required this.percent,
    required this.bps,
    this.usdValue,
  });

  factory JupiterRoutePlanStep.fromJson(Map<String, dynamic> json) {
    return JupiterRoutePlanStep(
      swapInfo: json.valueTo<JupiterSwapInfo, Map<String, dynamic>>(
        key: 'swapInfo',
        parse: (v) => JupiterSwapInfo.fromJson(v),
      ),
      percent: json.valueAsNum<num>('percent'),
      bps: json.valueAsNum<num>('bps'),
      usdValue: json.valueAsNum<num?>('usdValue'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'swapInfo': swapInfo.toJson(config: config),
    'percent': percent,
    'bps': bps,
    'usdValue': usdValue,
  });
}

class JupiterSwapEvent {
  final String? inputMint;
  final String? inputAmount;
  final String? outputMint;
  final String? outputAmount;

  const JupiterSwapEvent({
    this.inputMint,
    this.inputAmount,
    this.outputMint,
    this.outputAmount,
  });

  factory JupiterSwapEvent.fromJson(Map<String, dynamic> json) {
    return JupiterSwapEvent(
      inputMint: (json['inputMint'] is num
          ? json['inputMint'].toString()
          : json.valueAsString<String?>('inputMint')),
      inputAmount: (json['inputAmount'] is num
          ? json['inputAmount'].toString()
          : json.valueAsString<String?>('inputAmount')),
      outputMint: (json['outputMint'] is num
          ? json['outputMint'].toString()
          : json.valueAsString<String?>('outputMint')),
      outputAmount: (json['outputAmount'] is num
          ? json['outputAmount'].toString()
          : json.valueAsString<String?>('outputAmount')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'inputMint': inputMint,
    'inputAmount': inputAmount,
    'outputMint': outputMint,
    'outputAmount': outputAmount,
  });
}

class JupiterSwapInfo {
  final String ammKey;
  final String label;
  final String inputMint;
  final String outputMint;
  final String inAmount;
  final String outAmount;

  const JupiterSwapInfo({
    required this.ammKey,
    required this.label,
    required this.inputMint,
    required this.outputMint,
    required this.inAmount,
    required this.outAmount,
  });

  factory JupiterSwapInfo.fromJson(Map<String, dynamic> json) {
    return JupiterSwapInfo(
      ammKey: (json['ammKey'] is num
          ? json['ammKey'].toString()
          : json.valueAsString<String>('ammKey')),
      label: (json['label'] is num
          ? json['label'].toString()
          : json.valueAsString<String>('label')),
      inputMint: (json['inputMint'] is num
          ? json['inputMint'].toString()
          : json.valueAsString<String>('inputMint')),
      outputMint: (json['outputMint'] is num
          ? json['outputMint'].toString()
          : json.valueAsString<String>('outputMint')),
      inAmount: (json['inAmount'] is num
          ? json['inAmount'].toString()
          : json.valueAsString<String>('inAmount')),
      outAmount: (json['outAmount'] is num
          ? json['outAmount'].toString()
          : json.valueAsString<String>('outAmount')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'ammKey': ammKey,
    'label': label,
    'inputMint': inputMint,
    'outputMint': outputMint,
    'inAmount': inAmount,
    'outAmount': outAmount,
  });
}

class JupiterInstructionAccountsItem {
  final String pubkey;
  final bool isWritable;
  final bool isSigner;

  const JupiterInstructionAccountsItem({
    required this.pubkey,
    required this.isWritable,
    required this.isSigner,
  });

  factory JupiterInstructionAccountsItem.fromJson(Map<String, dynamic> json) {
    return JupiterInstructionAccountsItem(
      pubkey: (json['pubkey'] is num
          ? json['pubkey'].toString()
          : json.valueAsString<String>('pubkey')),
      isWritable: json.valueAsBool<bool>('isWritable'),
      isSigner: json.valueAsBool<bool>('isSigner'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'pubkey': pubkey,
    'isWritable': isWritable,
    'isSigner': isSigner,
  });
}
