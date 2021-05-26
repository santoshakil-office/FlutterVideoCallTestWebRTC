class PeerOfferModel {
  PeerOfferModel({required this.sdp, required this.type});

  PeerOfferModel.fromJson(Map<String, Object?> json)
      : this(
          sdp: json['sdp']! as String,
          type: json['type']! as String,
        );

  final String sdp;
  final String type;

  Map<String, dynamic> toJson() => {
        'sdp': sdp,
        'type': type,
      };
}
