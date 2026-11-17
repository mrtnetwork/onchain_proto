// GENERATED CODE - DO NOT MODIFY BY HAND
// Source: OpenAPI 3.0.0
// 1inch Swap API 6.1
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

class InchAccessSlotsDto {
  /// Contract address
  final String address;

  /// Storage keys accessed by the contract
  final List<String> storageKeys;

  const InchAccessSlotsDto({required this.address, required this.storageKeys});

  factory InchAccessSlotsDto.fromJson(Map<String, dynamic> json) {
    return InchAccessSlotsDto(
      address: (json['address'] is num
          ? json['address'].toString()
          : json.valueAsString<String>('address')),
      storageKeys: json.valueAsList<List<String>>('storageKeys'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'address': address,
    'storageKeys': storageKeys,
  });
}

/// GET /v6.1/{chainId}/approve/allowance (response)
class InchAllowanceResponse {
  /// Allowance amount
  final String allowance;

  const InchAllowanceResponse({required this.allowance});

  factory InchAllowanceResponse.fromJson(Map<String, dynamic> json) {
    return InchAllowanceResponse(
      allowance: (json['allowance'] is num
          ? json['allowance'].toString()
          : json.valueAsString<String>('allowance')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{'allowance': allowance});
}

/// GET /v6.1/{chainId}/approve/transaction (response)
class InchApproveCallDataResponse {
  /// The encoded data to call the approve method on the swapped token contract
  final String data;

  /// Network high gas price in wei
  final String gasPrice;

  /// Token address that will be allowed to exchange through 1inch Router
  final String to;

  /// Native token value in wei (for approve is always 0)
  final String value;

  const InchApproveCallDataResponse({
    required this.data,
    required this.gasPrice,
    required this.to,
    required this.value,
  });

  factory InchApproveCallDataResponse.fromJson(Map<String, dynamic> json) {
    return InchApproveCallDataResponse(
      data: (json['data'] is num
          ? json['data'].toString()
          : json.valueAsString<String>('data')),
      gasPrice: (json['gasPrice'] is num
          ? json['gasPrice'].toString()
          : json.valueAsString<String>('gasPrice')),
      to: (json['to'] is num
          ? json['to'].toString()
          : json.valueAsString<String>('to')),
      value: (json['value'] is num
          ? json['value'].toString()
          : json.valueAsString<String>('value')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'data': data,
    'gasPrice': gasPrice,
    'to': to,
    'value': value,
  });
}

class InchProtocolImage {
  /// Protocol id
  final String id;

  /// Protocol title
  final String title;

  /// Protocol logo image
  final String img;

  /// Protocol logo image in color
  final String imgColor;

  const InchProtocolImage({
    required this.id,
    required this.title,
    required this.img,
    required this.imgColor,
  });

  factory InchProtocolImage.fromJson(Map<String, dynamic> json) {
    return InchProtocolImage(
      id: (json['id'] is num
          ? json['id'].toString()
          : json.valueAsString<String>('id')),
      title: (json['title'] is num
          ? json['title'].toString()
          : json.valueAsString<String>('title')),
      img: (json['img'] is num
          ? json['img'].toString()
          : json.valueAsString<String>('img')),
      imgColor: (json['img_color'] is num
          ? json['img_color'].toString()
          : json.valueAsString<String>('img_color')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'id': id,
    'title': title,
    'img': img,
    'img_color': imgColor,
  });
}

/// GET /v6.1/{chainId}/liquidity-sources (response)
class InchProtocolsResponse {
  /// List of protocols that are available for routing in the 1inch Aggregation Protocol
  final List<InchProtocolImage> protocols;

  const InchProtocolsResponse({required this.protocols});

  factory InchProtocolsResponse.fromJson(Map<String, dynamic> json) {
    return InchProtocolsResponse(
      protocols: json
          .valueEnsureAsList<Map<String, dynamic>>('protocols')
          .map((e) => InchProtocolImage.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'protocols': protocols.map((e) => e.toJson(config: config)).toList(),
  });
}

/// GET /v6.1/{chainId}/quote (response)
class InchQuoteResponse {
  /// Source token info
  final InchTokenInfo? srcToken;

  /// Destination token info
  final InchTokenInfo? dstToken;

  /// Expected amount of destination token
  final String dstAmount;

  /// Selected protocols in a path
  final List<InchTokenSwaps>? protocols;

  /// Estimated gas
  final num? gas;

  const InchQuoteResponse({
    this.srcToken,
    this.dstToken,
    required this.dstAmount,
    this.protocols,
    this.gas,
  });

  factory InchQuoteResponse.fromJson(Map<String, dynamic> json) {
    return InchQuoteResponse(
      srcToken: json.valueTo<InchTokenInfo?, Map<String, dynamic>>(
        key: 'srcToken',
        parse: (v) => InchTokenInfo.fromJson(v),
      ),
      dstToken: json.valueTo<InchTokenInfo?, Map<String, dynamic>>(
        key: 'dstToken',
        parse: (v) => InchTokenInfo.fromJson(v),
      ),
      dstAmount: (json['dstAmount'] is num
          ? json['dstAmount'].toString()
          : json.valueAsString<String>('dstAmount')),
      protocols: json.hasValue('protocols')
          ? json
                .valueEnsureAsList<Map<String, dynamic>>('protocols')
                .map((e) => InchTokenSwaps.fromJson(e))
                .toList()
          : null,
      gas: json.valueAsNum<num?>('gas'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'srcToken': srcToken?.toJson(config: config),
    'dstToken': dstToken?.toJson(config: config),
    'dstAmount': dstAmount,
    'protocols': protocols?.map((e) => e.toJson(config: config)).toList(),
    'gas': gas,
  });
}

class InchSelectedLiquiditySource {
  /// The liquidity source id
  final String name;

  /// The distribution percent from total amount coming to specified destination token
  final num part_;

  const InchSelectedLiquiditySource({required this.name, required this.part_});

  factory InchSelectedLiquiditySource.fromJson(Map<String, dynamic> json) {
    return InchSelectedLiquiditySource(
      name: (json['name'] is num
          ? json['name'].toString()
          : json.valueAsString<String>('name')),
      part_: json.valueAsNum<num>('part'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{'name': name, 'part': part_});
}

class InchSelectedProtocol {
  /// Protocol id
  final String name;

  /// Protocol share
  final num part_;

  /// Source token to swap on protocol
  final String fromTokenAddress;

  /// Destination token to swap on protocol
  final String toTokenAddress;

  const InchSelectedProtocol({
    required this.name,
    required this.part_,
    required this.fromTokenAddress,
    required this.toTokenAddress,
  });

  factory InchSelectedProtocol.fromJson(Map<String, dynamic> json) {
    return InchSelectedProtocol(
      name: (json['name'] is num
          ? json['name'].toString()
          : json.valueAsString<String>('name')),
      part_: json.valueAsNum<num>('part'),
      fromTokenAddress: (json['fromTokenAddress'] is num
          ? json['fromTokenAddress'].toString()
          : json.valueAsString<String>('fromTokenAddress')),
      toTokenAddress: (json['toTokenAddress'] is num
          ? json['toTokenAddress'].toString()
          : json.valueAsString<String>('toTokenAddress')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'name': name,
    'part': part_,
    'fromTokenAddress': fromTokenAddress,
    'toTokenAddress': toTokenAddress,
  });
}

/// GET /v6.1/{chainId}/approve/spender (response)
class InchSpenderResponse {
  /// Address of the 1inch Router that is trusted to spend funds for the swap
  final String address;

  const InchSpenderResponse({required this.address});

  factory InchSpenderResponse.fromJson(Map<String, dynamic> json) {
    return InchSpenderResponse(
      address: (json['address'] is num
          ? json['address'].toString()
          : json.valueAsString<String>('address')),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{'address': address});
}

/// GET /v6.1/{chainId}/swap (response)
class InchSwapResponse {
  /// Source token info
  final InchTokenInfo? srcToken;

  /// Destination token info
  final InchTokenInfo? dstToken;

  /// Expected amount of destination token
  final String dstAmount;

  /// Selected protocols in a path
  final List<InchTokenSwaps>? protocols;

  /// Transaction object
  final InchTransactionData tx;

  /// State-override set for propAMM routes: the maker state lives off-chain, so pass this object as the third parameter of eth_call / eth_estimateGas to reproduce the quoted amounts. An empty object for routes without propAMM legs.
  final Map<String, dynamic> stateOverrides;

  const InchSwapResponse({
    this.srcToken,
    this.dstToken,
    required this.dstAmount,
    this.protocols,
    required this.tx,
    required this.stateOverrides,
  });

  factory InchSwapResponse.fromJson(Map<String, dynamic> json) {
    return InchSwapResponse(
      srcToken: json.valueTo<InchTokenInfo?, Map<String, dynamic>>(
        key: 'srcToken',
        parse: (v) => InchTokenInfo.fromJson(v),
      ),
      dstToken: json.valueTo<InchTokenInfo?, Map<String, dynamic>>(
        key: 'dstToken',
        parse: (v) => InchTokenInfo.fromJson(v),
      ),
      dstAmount: (json['dstAmount'] is num
          ? json['dstAmount'].toString()
          : json.valueAsString<String>('dstAmount')),
      protocols: json.hasValue('protocols')
          ? json
                .valueEnsureAsList<Map<String, dynamic>>('protocols')
                .map((e) => InchTokenSwaps.fromJson(e))
                .toList()
          : null,
      tx: json.valueTo<InchTransactionData, Map<String, dynamic>>(
        key: 'tx',
        parse: (v) => InchTransactionData.fromJson(v),
      ),
      stateOverrides: json.valueAsMap<Map<String, dynamic>>('stateOverrides'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'srcToken': srcToken?.toJson(config: config),
    'dstToken': dstToken?.toJson(config: config),
    'dstAmount': dstAmount,
    'protocols': protocols?.map((e) => e.toJson(config: config)).toList(),
    'tx': tx.toJson(config: config),
    'stateOverrides': stateOverrides,
  });
}

class InchTokenHop {
  /// The distribution percent from source token coming to destination token on this hop
  final num part_;

  /// Destination token address
  final String dst;

  /// Source token index in the path
  final num fromTokenId;

  /// Destination token index in the path
  final num toTokenId;

  /// The token split among different liquidity sources
  final List<InchSelectedLiquiditySource> protocols;

  const InchTokenHop({
    required this.part_,
    required this.dst,
    required this.fromTokenId,
    required this.toTokenId,
    required this.protocols,
  });

  factory InchTokenHop.fromJson(Map<String, dynamic> json) {
    return InchTokenHop(
      part_: json.valueAsNum<num>('part'),
      dst: (json['dst'] is num
          ? json['dst'].toString()
          : json.valueAsString<String>('dst')),
      fromTokenId: json.valueAsNum<num>('fromTokenId'),
      toTokenId: json.valueAsNum<num>('toTokenId'),
      protocols: json
          .valueEnsureAsList<Map<String, dynamic>>('protocols')
          .map((e) => InchSelectedLiquiditySource.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'part': part_,
    'dst': dst,
    'fromTokenId': fromTokenId,
    'toTokenId': toTokenId,
    'protocols': protocols.map((e) => e.toJson(config: config)).toList(),
  });
}

class InchTokenInfo {
  final String address;
  final String symbol;
  final String name;
  final num decimals;
  final String logoURI;
  final String? domainVersion;
  final bool? eip2612;
  final bool? isFoT;
  final List<String>? tags;

  const InchTokenInfo({
    required this.address,
    required this.symbol,
    required this.name,
    required this.decimals,
    required this.logoURI,
    this.domainVersion,
    this.eip2612,
    this.isFoT,
    this.tags,
  });

  factory InchTokenInfo.fromJson(Map<String, dynamic> json) {
    return InchTokenInfo(
      address: (json['address'] is num
          ? json['address'].toString()
          : json.valueAsString<String>('address')),
      symbol: (json['symbol'] is num
          ? json['symbol'].toString()
          : json.valueAsString<String>('symbol')),
      name: (json['name'] is num
          ? json['name'].toString()
          : json.valueAsString<String>('name')),
      decimals: json.valueAsNum<num>('decimals'),
      logoURI: (json['logoURI'] is num
          ? json['logoURI'].toString()
          : json.valueAsString<String>('logoURI')),
      domainVersion: (json['domainVersion'] is num
          ? json['domainVersion'].toString()
          : json.valueAsString<String?>('domainVersion')),
      eip2612: json.valueAsBool<bool?>('eip2612'),
      isFoT: json.valueAsBool<bool?>('isFoT'),
      tags: json.valueAsList<List<String>?>('tags'),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'address': address,
    'symbol': symbol,
    'name': name,
    'decimals': decimals,
    'logoURI': logoURI,
    'domainVersion': domainVersion,
    'eip2612': eip2612,
    'isFoT': isFoT,
    'tags': tags,
  });
}

class InchTokenSwaps {
  /// Source token address for the hops
  final String token;

  /// Swap hops from source token
  final List<InchTokenHop> hops;

  const InchTokenSwaps({required this.token, required this.hops});

  factory InchTokenSwaps.fromJson(Map<String, dynamic> json) {
    return InchTokenSwaps(
      token: (json['token'] is num
          ? json['token'].toString()
          : json.valueAsString<String>('token')),
      hops: json
          .valueEnsureAsList<Map<String, dynamic>>('hops')
          .map((e) => InchTokenHop.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'token': token,
    'hops': hops.map((e) => e.toJson(config: config)).toList(),
  });
}

class InchTransactionData {
  final String from;
  final String to;
  final String data;
  final String value;
  final String gasPrice;
  final num gas;

  /// Simulated gas used (from `eth_createAccessList`). Set only when access lists are enabled for the chain and the returned list is non-empty.
  final num? gasUsed;

  /// EIP-2930 access list. When the client sets createAccessList=true, this field and `gasUsed` are always present; if no slots are needed, `accessList` may be an empty array and `gasUsed` is set to the transaction gas limit.
  final List<InchAccessSlotsDto>? accessList;

  const InchTransactionData({
    required this.from,
    required this.to,
    required this.data,
    required this.value,
    required this.gasPrice,
    required this.gas,
    this.gasUsed,
    this.accessList,
  });

  factory InchTransactionData.fromJson(Map<String, dynamic> json) {
    return InchTransactionData(
      from: (json['from'] is num
          ? json['from'].toString()
          : json.valueAsString<String>('from')),
      to: (json['to'] is num
          ? json['to'].toString()
          : json.valueAsString<String>('to')),
      data: (json['data'] is num
          ? json['data'].toString()
          : json.valueAsString<String>('data')),
      value: (json['value'] is num
          ? json['value'].toString()
          : json.valueAsString<String>('value')),
      gasPrice: (json['gasPrice'] is num
          ? json['gasPrice'].toString()
          : json.valueAsString<String>('gasPrice')),
      gas: json.valueAsNum<num>('gas'),
      gasUsed: json.valueAsNum<num?>('gasUsed'),
      accessList: json.hasValue('accessList')
          ? json
                .valueEnsureAsList<Map<String, dynamic>>('accessList')
                .map((e) => InchAccessSlotsDto.fromJson(e))
                .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson({
    JsonifyConfig config = DefaultJsonifyConfig.defaultConfig,
  }) => config.encodeMap(<String, dynamic>{
    'from': from,
    'to': to,
    'data': data,
    'value': value,
    'gasPrice': gasPrice,
    'gas': gas,
    'gasUsed': gasUsed,
    'accessList': accessList?.map((e) => e.toJson(config: config)).toList(),
  });
}
