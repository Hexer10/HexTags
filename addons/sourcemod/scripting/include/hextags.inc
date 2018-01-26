/*
 * HexTags Inc File.
 * by: Hexah
 * https://github.com/Hexer10/HexTags
 * 
 * Copyright (C) 2017 Mattia (Hexah|Hexer10|Papero)
 *
 * This file is part of the HexTags SourceMod Plugin.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>. 
 */
#if defined _hextags_included
	#endinput
#endif
#define _hextags_included


public SharedPlugin __pl_hextags =
{
	name = "hextags",
	file = "hextags.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public void __pl_hextags_SetNTVOptional()
{
	MarkNativeAsOptional("HexTags_GetClientTag");
	MarkNativeAsOptional("HexTags_SetClientTag");
	MarkNativeAsOptional("HexTags_ResetClientTags");
}
#endif

enum eTags
{
	ScoreTag,
	ChatTag,
	ChatColor,
	NameColor
}

/** 
 * Returns an HexTags client tag.
 *
 * @param				Client Index.
 * @TagType				Tag type.
 * @buffer				String to store the tag in.
 * @maxlength			Maximum size of string buffer.
 *
 * @error				Invalid client index, or not connected.
 */
native void HexTags_GetClientTag(int client, eTags TagType, char[] buffer, int maxlength);

/** 
 * Sets an HexTags client tag.
 * This is resetted everytime that "HexTags_OnTagsUpdated" is called.
 *
 * @param				Client Index.
 * @TagType				Tag type.
 * @Tag					New client tag.
 * 
 * @error				Invalid client index, or not connected.
 */
native void HexTags_SetClientTag(int client, eTags TagType, char[] Tag);

/** 
 * Update the client tags to its default (from config).
 *
 * @param				Client Index.
 *
 * @error				Invalid client index, or not connected.
 */
native void HexTags_ResetClientTags(int client);

/** 
 * Called when the client tags gets updated.
 *
 * @param				Client Index.
 */
forward void HexTags_OnTagsUpdated(int client);
