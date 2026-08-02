class BbbsPost {
  final String filename;
  final String board;
  final String? section;
  final String boardName;
  final String? sectionName;
  final String title;
  final String content;
  final String author;
  final String? authorAvatar;
  final String? authorTitle;
  final dynamic time;
  final dynamic lastActiveTime;
  final List<String> tags;
  final List<dynamic> likes;
  final int shares;
  final dynamic pinned;
  final int views;
  final String status;
  final int commentsCount;
  final List<BbbsComment> comments;
  final int heat;
  
  // Recommendation fields
  final int? recommendationScore;
  final String? recommendationReason;
  final String? ipLocation;

  BbbsPost({
    required this.filename,
    required this.board,
    this.section,
    required this.boardName,
    this.sectionName,
    required this.title,
    required this.content,
    required this.author,
    this.authorAvatar,
    this.authorTitle,
    required this.time,
    required this.lastActiveTime,
    required this.tags,
    required this.likes,
    required this.shares,
    this.pinned,
    required this.views,
    required this.status,
    required this.commentsCount,
    required this.comments,
    required this.heat,
    this.recommendationScore,
    this.recommendationReason,
    this.ipLocation,
  });

  factory BbbsPost.fromJson(Map<String, dynamic> json) {
    return BbbsPost(
      filename: json['filename'] ?? '',
      board: json['board'] ?? '',
      section: json['section'],
      boardName: json['board_name'] ?? json['board'] ?? '',
      sectionName: json['section_name'] ?? json['section'],
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      author: json['author'] ?? '',
      authorAvatar: json['author_avatar'] ?? json['authorAvatar'],
      authorTitle: json['author_title'] ?? json['authorTitle'],
      time: json['time'],
      lastActiveTime: json['last_active_time'] ?? json['lastActiveTime'],
      tags: List<String>.from(json['tags'] ?? []),
      likes: List<dynamic>.from(json['likes'] ?? []),
      shares: json['shares'] ?? 0,
      pinned: json['pinned'],
      views: json['views'] ?? 0,
      status: json['status'] ?? '',
      commentsCount: json['commentsCount'] ?? json['comments_count'] ?? 0,
      comments: (json['comments'] as List? ?? [])
          .map((e) => BbbsComment.fromJson(e))
          .toList(),
      heat: json['heat'] ?? 0,
      recommendationScore: json['recommendationScore'],
      recommendationReason: json['reason'],
      ipLocation: json['ip_location'],
    );
  }
}

class BbbsComment {
  final int id;
  final String author;
  final String? authorAvatar;
  final String content;
  final dynamic time;
  final List<dynamic> likes;
  final int? parentId;
  final int? replyToId;

  BbbsComment({
    required this.id,
    required this.author,
    this.authorAvatar,
    required this.content,
    required this.time,
    required this.likes,
    this.parentId,
    this.replyToId,
  });

  factory BbbsComment.fromJson(Map<String, dynamic> json) {
    return BbbsComment(
      id: json['id'] ?? json['commentId'] ?? 0,
      author: json['author'] ?? '',
      authorAvatar: json['author_avatar'],
      content: json['content'] ?? '',
      time: json['time'],
      likes: List<dynamic>.from(json['likes'] ?? []),
      parentId: json['parent_id'] ?? json['parentId'],
      replyToId: json['reply_to_id'] ?? json['replyToId'],
    );
  }
}
