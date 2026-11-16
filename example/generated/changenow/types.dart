// GENERATED CODE - DO NOT MODIFY BY HAND
// Source: OpenAPI 3.0.3
// ChangeNOW API 2.0
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

enum ChangeNowCreateExchangeRequestFlow {
  standard("standard"),
  fixedRate("fixed-rate");

  final String value;
  const ChangeNowCreateExchangeRequestFlow(this.value);

  static ChangeNowCreateExchangeRequestFlow fromJson(dynamic json) {
    final value = json is String ? json : json?.toString();
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw BuError(
        DefaultErrorType.invalidArgument,
        "No matching ChangeNowCreateExchangeRequestFlow found for the given value. $value",
      ),
    );
  }

  String toJson({JsonifyConfig config = DefaultJsonifyConfig.defaultConfig}) =>
      value;
}

enum ChangeNowCreateExchangeRequestType {
  direct("direct"),
  reverse("reverse");

  final String value;
  const ChangeNowCreateExchangeRequestType(this.value);

  static ChangeNowCreateExchangeRequestType fromJson(dynamic json) {
    final value = json is String ? json : json?.toString();
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw BuError(
        DefaultErrorType.invalidArgument,
        "No matching ChangeNowCreateExchangeRequestType found for the given value. $value",
      ),
    );
  }

  String toJson({JsonifyConfig config = DefaultJsonifyConfig.defaultConfig}) =>
      value;
}

enum ChangeNowTransactionStatusStatus {
  new_("new"),
  waiting("waiting"),
  confirming("confirming"),
  exchanging("exchanging"),
  sending("sending"),
  finished("finished"),
  failed("failed"),
  refunded("refunded"),
  verifying("verifying");

  final String value;
  const ChangeNowTransactionStatusStatus(this.value);

  static ChangeNowTransactionStatusStatus fromJson(dynamic json) {
    final value = json is String ? json : json?.toString();
    return values.firstWhere(
      (e) => e.value == value,
      orElse: () => throw BuError(
        DefaultErrorType.invalidArgument,
        "No matching ChangeNowTransactionStatusStatus found for the given value. $value",
      ),
    );
  }

  String toJson({JsonifyConfig config = DefaultJsonifyConfig.defaultConfig}) =>
      value;
}

/// POST /exchange (request)
class ChangeNowCreateExchangeRequest {
  final String fromCurrency;
  final String toCurrency;
  final num fromAmount;

  /// Destination wallet address
  final String address;
  final String? fromNetwork;
  final String? toNetwork;
  final ChangeNowCreateExchangeRequestFlow? flow;
  final ChangeNowCreateExchangeRequestType? type;

  /// Rate ID for fixed-rate exchanges
  final String? rateId;

  /// Extra ID (memo/tag) if required by destination
  final String? extraId;

  /// Refund address in case of issues
  final String? refundAddress;
  final String? refundExtraId;
  final String? contactEmail;
  final String? userId;

  const ChangeNowCreateExchangeRequest({
    required this.fromCurrency,
    required this.toCurrency,
    required this.fromAmount,
    required this.address,
    this.fromNetwork,
    this.toNetwork,
    this.flow,
    this.type,
    this.rateId,
    this.extraId,
    this.refundAddress,
    this.refundExtraId,
    this.contactEmail,
    this.userId,
  });

  factory ChangeNowCreateExchangeRequest.fromJson(Map<String, dynamic> json) {
    return ChangeNowCreateExchangeRequest(
      fromCurrency: (json['fromCurrency'] is num
          ? json['fromCurrency'].toString()
          : json.valueAsString<String>('fromCurrency')),
      toCurrency: (json['toCurrency'] is num
          ? json['toCurrency'].toString()
          : json.valueAsString<String>('toCurrency')),
      fromAmount: json.valueAsNum<num>('fromAmount'),
      address: (json['address'] is num
          ? json['address'].toString()
          : json.valueAsString<String>('address')),
      fromNetwork: (json['fromNetwork'] is num
          ? json['fromNetwork'].toString()
          : json.valueAsString<String?>('fromNetwork')),
      toNetwork: (json['toNetwork'] is num
          ? json['toNetwork'].toString()
          : json.valueAsString<String?>('toNetwork')),
      flow: json.valueTo<ChangeNowCreateExchangeRequestFlow?, Object>(
        key: 'flow',
        parse: (e) =>
            ChangeNowCreateExchangeRequestFlow.fromJson(JsonParser.valueAs(e)),
      ),
      type: json.valueTo<ChangeNowCreateExchangeRequestType?, Object>(
        key: 'type',
        parse: (e) =>
            ChangeNowCreateExchangeRequestType.fromJson(JsonParser.valueAs(e)),
      ),
      rateId: (json['rateId'] is num
          ? json['rateId'].toString()
          : json.valueAsString<String?>('rateId')),
      extraId: (json['extraId'] is num
          ? json['extraId'].toString()
          : json.valueAsString<String?>('extraId')),
      refundAddress: (json['refundAddress'] is num
          ? json['refundAddress'].toString()
          : json.valueAsString<String?>('refundAddress')),
      refundExtraId: (json['refundExtraId'] is num
          ? json['refundExtraId'].toString()
          : json.valueAsString<String?>('refundExtraId')),
      contactEmail: (json['contactEmail'] is num
          ? json['contactEmail'].toString()
          : json.valueAsString<String?>('contactEmail')),
      userId: (json['userId'] is num
          ? json['userId'].toString()
          : json.valueAsString<String?>('userId')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'fromCurrency': fromCurrency,
    'toCurrency': toCurrency,
    'fromAmount': fromAmount,
    'address': address,
    'fromNetwork': fromNetwork,
    'toNetwork': toNetwork,
    'flow': flow?.toJson(config: config),
    'type': type?.toJson(config: config),
    'rateId': rateId,
    'extraId': extraId,
    'refundAddress': refundAddress,
    'refundExtraId': refundExtraId,
    'contactEmail': contactEmail,
    'userId': userId,
  });
}

class ChangeNowCurrency {
  /// Currency ticker
  final String? ticker;

  /// Currency full name
  final String? name;

  /// Currency icon URL
  final String? image;
  final bool? hasExternalId;
  final bool? isFiat;
  final bool? featured;
  final bool? isStable;
  final bool? supportsFixedRate;
  final String? network;
  final String? tokenContract;
  final bool? buy;
  final bool? sell;

  const ChangeNowCurrency({
    this.ticker,
    this.name,
    this.image,
    this.hasExternalId,
    this.isFiat,
    this.featured,
    this.isStable,
    this.supportsFixedRate,
    this.network,
    this.tokenContract,
    this.buy,
    this.sell,
  });

  factory ChangeNowCurrency.fromJson(Map<String, dynamic> json) {
    return ChangeNowCurrency(
      ticker: (json['ticker'] is num
          ? json['ticker'].toString()
          : json.valueAsString<String?>('ticker')),
      name: (json['name'] is num
          ? json['name'].toString()
          : json.valueAsString<String?>('name')),
      image: (json['image'] is num
          ? json['image'].toString()
          : json.valueAsString<String?>('image')),
      hasExternalId: json.valueAsBool<bool?>('hasExternalId'),
      isFiat: json.valueAsBool<bool?>('isFiat'),
      featured: json.valueAsBool<bool?>('featured'),
      isStable: json.valueAsBool<bool?>('isStable'),
      supportsFixedRate: json.valueAsBool<bool?>('supportsFixedRate'),
      network: (json['network'] is num
          ? json['network'].toString()
          : json.valueAsString<String?>('network')),
      tokenContract: (json['tokenContract'] is num
          ? json['tokenContract'].toString()
          : json.valueAsString<String?>('tokenContract')),
      buy: json.valueAsBool<bool?>('buy'),
      sell: json.valueAsBool<bool?>('sell'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'ticker': ticker,
    'name': name,
    'image': image,
    'hasExternalId': hasExternalId,
    'isFiat': isFiat,
    'featured': featured,
    'isStable': isStable,
    'supportsFixedRate': supportsFixedRate,
    'network': network,
    'tokenContract': tokenContract,
    'buy': buy,
    'sell': sell,
  });
}

/// GET /exchange/currencies (response)
/// GET /exchange/estimated-amount (response)
/// GET /exchange/min-amount (response)
/// GET /exchange/range (response)
/// POST /exchange (response)
/// GET /exchange/by-id (response)
/// GET /exchange/market-info/available-pairs (response)
/// GET /fiat-currencies/fiat (response)
class ChangeNowErrorResponse {
  final String? error;
  final String? message;

  const ChangeNowErrorResponse({this.error, this.message});

  factory ChangeNowErrorResponse.fromJson(Map<String, dynamic> json) {
    return ChangeNowErrorResponse(
      error: (json['error'] is num
          ? json['error'].toString()
          : json.valueAsString<String?>('error')),
      message: (json['message'] is num
          ? json['message'].toString()
          : json.valueAsString<String?>('message')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{'error': error, 'message': message});
}

/// GET /exchange/estimated-amount (response)
class ChangeNowEstimatedAmount {
  final String? fromCurrency;
  final String? fromNetwork;
  final String? toCurrency;
  final String? toNetwork;
  final String? flow;
  final String? type;
  final String? rateId;
  final String? validUntil;
  final String? transactionSpeedForecast;
  final String? warningMessage;
  final num? fromAmount;
  final num? toAmount;

  const ChangeNowEstimatedAmount({
    this.fromCurrency,
    this.fromNetwork,
    this.toCurrency,
    this.toNetwork,
    this.flow,
    this.type,
    this.rateId,
    this.validUntil,
    this.transactionSpeedForecast,
    this.warningMessage,
    this.fromAmount,
    this.toAmount,
  });

  factory ChangeNowEstimatedAmount.fromJson(Map<String, dynamic> json) {
    return ChangeNowEstimatedAmount(
      fromCurrency: (json['fromCurrency'] is num
          ? json['fromCurrency'].toString()
          : json.valueAsString<String?>('fromCurrency')),
      fromNetwork: (json['fromNetwork'] is num
          ? json['fromNetwork'].toString()
          : json.valueAsString<String?>('fromNetwork')),
      toCurrency: (json['toCurrency'] is num
          ? json['toCurrency'].toString()
          : json.valueAsString<String?>('toCurrency')),
      toNetwork: (json['toNetwork'] is num
          ? json['toNetwork'].toString()
          : json.valueAsString<String?>('toNetwork')),
      flow: (json['flow'] is num
          ? json['flow'].toString()
          : json.valueAsString<String?>('flow')),
      type: (json['type'] is num
          ? json['type'].toString()
          : json.valueAsString<String?>('type')),
      rateId: (json['rateId'] is num
          ? json['rateId'].toString()
          : json.valueAsString<String?>('rateId')),
      validUntil: (json['validUntil'] is num
          ? json['validUntil'].toString()
          : json.valueAsString<String?>('validUntil')),
      transactionSpeedForecast: (json['transactionSpeedForecast'] is num
          ? json['transactionSpeedForecast'].toString()
          : json.valueAsString<String?>('transactionSpeedForecast')),
      warningMessage: (json['warningMessage'] is num
          ? json['warningMessage'].toString()
          : json.valueAsString<String?>('warningMessage')),
      fromAmount: json.valueAsNum<num?>('fromAmount'),
      toAmount: json.valueAsNum<num?>('toAmount'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'fromCurrency': fromCurrency,
    'fromNetwork': fromNetwork,
    'toCurrency': toCurrency,
    'toNetwork': toNetwork,
    'flow': flow,
    'type': type,
    'rateId': rateId,
    'validUntil': validUntil,
    'transactionSpeedForecast': transactionSpeedForecast,
    'warningMessage': warningMessage,
    'fromAmount': fromAmount,
    'toAmount': toAmount,
  });
}

/// GET /exchange/range (response)
class ChangeNowExchangeRange {
  final String? fromCurrency;
  final String? fromNetwork;
  final String? toCurrency;
  final String? toNetwork;
  final String? flow;
  final num? minAmount;
  final num? maxAmount;

  const ChangeNowExchangeRange({
    this.fromCurrency,
    this.fromNetwork,
    this.toCurrency,
    this.toNetwork,
    this.flow,
    this.minAmount,
    this.maxAmount,
  });

  factory ChangeNowExchangeRange.fromJson(Map<String, dynamic> json) {
    return ChangeNowExchangeRange(
      fromCurrency: (json['fromCurrency'] is num
          ? json['fromCurrency'].toString()
          : json.valueAsString<String?>('fromCurrency')),
      fromNetwork: (json['fromNetwork'] is num
          ? json['fromNetwork'].toString()
          : json.valueAsString<String?>('fromNetwork')),
      toCurrency: (json['toCurrency'] is num
          ? json['toCurrency'].toString()
          : json.valueAsString<String?>('toCurrency')),
      toNetwork: (json['toNetwork'] is num
          ? json['toNetwork'].toString()
          : json.valueAsString<String?>('toNetwork')),
      flow: (json['flow'] is num
          ? json['flow'].toString()
          : json.valueAsString<String?>('flow')),
      minAmount: json.valueAsNum<num?>('minAmount'),
      maxAmount: json.valueAsNum<num?>('maxAmount'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'fromCurrency': fromCurrency,
    'fromNetwork': fromNetwork,
    'toCurrency': toCurrency,
    'toNetwork': toNetwork,
    'flow': flow,
    'minAmount': minAmount,
    'maxAmount': maxAmount,
  });
}

class ChangeNowFiatCurrency {
  final String? ticker;
  final String? name;
  final String? image;

  const ChangeNowFiatCurrency({this.ticker, this.name, this.image});

  factory ChangeNowFiatCurrency.fromJson(Map<String, dynamic> json) {
    return ChangeNowFiatCurrency(
      ticker: (json['ticker'] is num
          ? json['ticker'].toString()
          : json.valueAsString<String?>('ticker')),
      name: (json['name'] is num
          ? json['name'].toString()
          : json.valueAsString<String?>('name')),
      image: (json['image'] is num
          ? json['image'].toString()
          : json.valueAsString<String?>('image')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'ticker': ticker,
    'name': name,
    'image': image,
  });
}

/// GET /exchange/min-amount (response)
class ChangeNowMinAmount {
  final String? fromCurrency;
  final String? fromNetwork;
  final String? toCurrency;
  final String? toNetwork;
  final String? flow;
  final num? minAmount;

  const ChangeNowMinAmount({
    this.fromCurrency,
    this.fromNetwork,
    this.toCurrency,
    this.toNetwork,
    this.flow,
    this.minAmount,
  });

  factory ChangeNowMinAmount.fromJson(Map<String, dynamic> json) {
    return ChangeNowMinAmount(
      fromCurrency: (json['fromCurrency'] is num
          ? json['fromCurrency'].toString()
          : json.valueAsString<String?>('fromCurrency')),
      fromNetwork: (json['fromNetwork'] is num
          ? json['fromNetwork'].toString()
          : json.valueAsString<String?>('fromNetwork')),
      toCurrency: (json['toCurrency'] is num
          ? json['toCurrency'].toString()
          : json.valueAsString<String?>('toCurrency')),
      toNetwork: (json['toNetwork'] is num
          ? json['toNetwork'].toString()
          : json.valueAsString<String?>('toNetwork')),
      flow: (json['flow'] is num
          ? json['flow'].toString()
          : json.valueAsString<String?>('flow')),
      minAmount: json.valueAsNum<num?>('minAmount'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'fromCurrency': fromCurrency,
    'fromNetwork': fromNetwork,
    'toCurrency': toCurrency,
    'toNetwork': toNetwork,
    'flow': flow,
    'minAmount': minAmount,
  });
}

/// POST /exchange (response)
class ChangeNowTransaction {
  final String? id;
  final String? fromCurrency;
  final String? fromNetwork;
  final String? toCurrency;
  final String? toNetwork;
  final num? fromAmount;
  final num? toAmount;
  final String? flow;
  final String? type;

  /// Address to send funds to
  final String? payinAddress;
  final String? payoutAddress;
  final String? payinExtraId;
  final String? refundAddress;
  final String? refundExtraId;

  const ChangeNowTransaction({
    this.id,
    this.fromCurrency,
    this.fromNetwork,
    this.toCurrency,
    this.toNetwork,
    this.fromAmount,
    this.toAmount,
    this.flow,
    this.type,
    this.payinAddress,
    this.payoutAddress,
    this.payinExtraId,
    this.refundAddress,
    this.refundExtraId,
  });

  factory ChangeNowTransaction.fromJson(Map<String, dynamic> json) {
    return ChangeNowTransaction(
      id: (json['id'] is num
          ? json['id'].toString()
          : json.valueAsString<String?>('id')),
      fromCurrency: (json['fromCurrency'] is num
          ? json['fromCurrency'].toString()
          : json.valueAsString<String?>('fromCurrency')),
      fromNetwork: (json['fromNetwork'] is num
          ? json['fromNetwork'].toString()
          : json.valueAsString<String?>('fromNetwork')),
      toCurrency: (json['toCurrency'] is num
          ? json['toCurrency'].toString()
          : json.valueAsString<String?>('toCurrency')),
      toNetwork: (json['toNetwork'] is num
          ? json['toNetwork'].toString()
          : json.valueAsString<String?>('toNetwork')),
      fromAmount: json.valueAsNum<num?>('fromAmount'),
      toAmount: json.valueAsNum<num?>('toAmount'),
      flow: (json['flow'] is num
          ? json['flow'].toString()
          : json.valueAsString<String?>('flow')),
      type: (json['type'] is num
          ? json['type'].toString()
          : json.valueAsString<String?>('type')),
      payinAddress: (json['payinAddress'] is num
          ? json['payinAddress'].toString()
          : json.valueAsString<String?>('payinAddress')),
      payoutAddress: (json['payoutAddress'] is num
          ? json['payoutAddress'].toString()
          : json.valueAsString<String?>('payoutAddress')),
      payinExtraId: (json['payinExtraId'] is num
          ? json['payinExtraId'].toString()
          : json.valueAsString<String?>('payinExtraId')),
      refundAddress: (json['refundAddress'] is num
          ? json['refundAddress'].toString()
          : json.valueAsString<String?>('refundAddress')),
      refundExtraId: (json['refundExtraId'] is num
          ? json['refundExtraId'].toString()
          : json.valueAsString<String?>('refundExtraId')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'id': id,
    'fromCurrency': fromCurrency,
    'fromNetwork': fromNetwork,
    'toCurrency': toCurrency,
    'toNetwork': toNetwork,
    'fromAmount': fromAmount,
    'toAmount': toAmount,
    'flow': flow,
    'type': type,
    'payinAddress': payinAddress,
    'payoutAddress': payoutAddress,
    'payinExtraId': payinExtraId,
    'refundAddress': refundAddress,
    'refundExtraId': refundExtraId,
  });
}

/// GET /exchange/by-id (response)
class ChangeNowTransactionStatus {
  final String? id;
  final ChangeNowTransactionStatusStatus? status;
  final String? fromCurrency;
  final String? toCurrency;
  final num? expectedSendAmount;
  final num? expectedReceiveAmount;
  final num? amountFrom;
  final num? amountTo;
  final String? payinAddress;
  final String? payoutAddress;
  final String? payinHash;
  final String? payoutHash;
  final String? createdAt;
  final String? updatedAt;

  const ChangeNowTransactionStatus({
    this.id,
    this.status,
    this.fromCurrency,
    this.toCurrency,
    this.expectedSendAmount,
    this.expectedReceiveAmount,
    this.amountFrom,
    this.amountTo,
    this.payinAddress,
    this.payoutAddress,
    this.payinHash,
    this.payoutHash,
    this.createdAt,
    this.updatedAt,
  });

  factory ChangeNowTransactionStatus.fromJson(Map<String, dynamic> json) {
    return ChangeNowTransactionStatus(
      id: (json['id'] is num
          ? json['id'].toString()
          : json.valueAsString<String?>('id')),
      status: json.valueTo<ChangeNowTransactionStatusStatus?, Object>(
        key: 'status',
        parse: (e) =>
            ChangeNowTransactionStatusStatus.fromJson(JsonParser.valueAs(e)),
      ),
      fromCurrency: (json['fromCurrency'] is num
          ? json['fromCurrency'].toString()
          : json.valueAsString<String?>('fromCurrency')),
      toCurrency: (json['toCurrency'] is num
          ? json['toCurrency'].toString()
          : json.valueAsString<String?>('toCurrency')),
      expectedSendAmount: json.valueAsNum<num?>('expectedSendAmount'),
      expectedReceiveAmount: json.valueAsNum<num?>('expectedReceiveAmount'),
      amountFrom: json.valueAsNum<num?>('amountFrom'),
      amountTo: json.valueAsNum<num?>('amountTo'),
      payinAddress: (json['payinAddress'] is num
          ? json['payinAddress'].toString()
          : json.valueAsString<String?>('payinAddress')),
      payoutAddress: (json['payoutAddress'] is num
          ? json['payoutAddress'].toString()
          : json.valueAsString<String?>('payoutAddress')),
      payinHash: (json['payinHash'] is num
          ? json['payinHash'].toString()
          : json.valueAsString<String?>('payinHash')),
      payoutHash: (json['payoutHash'] is num
          ? json['payoutHash'].toString()
          : json.valueAsString<String?>('payoutHash')),
      createdAt: (json['createdAt'] is num
          ? json['createdAt'].toString()
          : json.valueAsString<String?>('createdAt')),
      updatedAt: (json['updatedAt'] is num
          ? json['updatedAt'].toString()
          : json.valueAsString<String?>('updatedAt')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'id': id,
    'status': status?.toJson(config: config),
    'fromCurrency': fromCurrency,
    'toCurrency': toCurrency,
    'expectedSendAmount': expectedSendAmount,
    'expectedReceiveAmount': expectedReceiveAmount,
    'amountFrom': amountFrom,
    'amountTo': amountTo,
    'payinAddress': payinAddress,
    'payoutAddress': payoutAddress,
    'payinHash': payinHash,
    'payoutHash': payoutHash,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  });
}
